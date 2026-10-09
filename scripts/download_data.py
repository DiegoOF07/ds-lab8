#!/usr/bin/env python3
"""Descarga los archivos Parquet del NYC TLC Trip Record Data.

Descarga los registros de viajes de taxis amarillos (yellow) y verdes (green)
de los anios definidos en ANIOS (por defecto 2024, 2025 y 2026), o de los que se
indiquen con --anio. Agregar un anio al laboratorio solo requiere agregarlo a
ANIOS: los archivos ya descargados de otros anios no se tocan.

Fuente oficial de los datos:
    https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page

Uso:
    python scripts/download_data.py                      # todos los anios de ANIOS
    python scripts/download_data.py --anio 2024          # un solo anio
    python scripts/download_data.py --anio 2024 2026 --taxi green

Los archivos se guardan en:
    data/raw/<tipo>/<anio>/<nombre-original>.parquet

Comportamiento:
  - La TLC publica cada mes con varias semanas de atraso, por lo que no todos
    los meses del anio en curso existen todavia. El script consulta al servidor
    que meses estan publicados en lugar de suponerlos.
  - Un archivo que ya existe localmente no se vuelve a descargar, siempre que
    su tamanio coincida con el publicado (Content-Length). Si difiere se
    considera incompleto y se descarga de nuevo.
  - Cada archivo se valida leyendo su metadata Parquet (cantidad de filas).
  - Al terminar se escribe data/raw/manifest_<anio>.csv con el detalle de
    cada archivo, que sirve para verificar que la descarga esta completa.
  - La descarga se hace sobre un nombre temporal y solo se renombra al
    terminar, de modo que una interrupcion no deja archivos .parquet a medias.
  - Tambien descarga la tabla de zonas de la TLC (data/raw/taxi_zone_lookup.csv),
    que traduce PULocationID/DOLocationID a borough y zona.
"""

import argparse
import csv
import sys
from datetime import date
from pathlib import Path

import pyarrow.parquet as pq
import requests

ANIOS = (2024, 2025, 2026)  # anios que forman parte del laboratorio
PRIMER_ANIO_TLC = 2009      # primer anio publicado por la TLC
TIPOS_TAXI = ("yellow", "green")
URL_BASE = "https://d37ci6vzurychx.cloudfront.net/trip-data"
DIR_DESTINO = Path("data/raw")
URL_ZONAS = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
ARCHIVO_ZONAS = DIR_DESTINO / "taxi_zone_lookup.csv"

TIEMPO_ESPERA = 60          # segundos por peticion
INTENTOS = 3                # intentos por archivo antes de darse por vencido
BLOQUE = 1024 * 1024        # 1 MiB por bloque de descarga
SUFIJO_TEMPORAL = ".part"


def construir_nombre(tipo: str, anio: int, mes: int) -> str:
    """Nombre del archivo publicado por la TLC, p. ej. yellow_tripdata_2026-01.parquet."""
    return f"{tipo}_tripdata_{anio}-{mes:02d}.parquet"


def construir_url(tipo: str, anio: int, mes: int) -> str:
    """URL completa del archivo Parquet mensual."""
    return f"{URL_BASE}/{construir_nombre(tipo, anio, mes)}"


def ruta_destino(tipo: str, anio: int, mes: int) -> Path:
    """Ruta local donde se guarda el archivo."""
    return DIR_DESTINO / tipo / str(anio) / construir_nombre(tipo, anio, mes)


def ruta_manifiesto(anio: int) -> Path:
    """Manifiesto con el detalle de los archivos de un anio."""
    return DIR_DESTINO / f"manifest_{anio}.csv"


class SinConexion(Exception):
    """El servidor no respondio, por lo que no se sabe si el archivo existe."""


def tamanio_remoto(url: str) -> int | None:
    """Content-Length del archivo en el servidor, o None si no esta publicado."""
    try:
        respuesta = requests.head(url, timeout=TIEMPO_ESPERA, allow_redirects=True)
    except requests.RequestException as error:
        raise SinConexion(str(error)) from error
    if not respuesta.ok:
        return None
    return int(respuesta.headers.get("Content-Length", 0)) or None


def filas_parquet(ruta: Path) -> int:
    """Cantidad de filas segun el footer del Parquet; falla si no es legible."""
    return pq.read_metadata(ruta).num_rows


def formato_tamanio(n: float) -> str:
    for unidad in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unidad == "GiB":
            return f"{n:.1f} {unidad}"
        n /= 1024
    return f"{n:.1f} GiB"


def descargar_archivo(url: str, destino: Path, esperado: int) -> int:
    """Descarga `url` en `destino` y verifica que pese `esperado` bytes."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    temporal = destino.with_name(destino.name + SUFIJO_TEMPORAL)

    ultimo_error = None
    for intento in range(1, INTENTOS + 1):
        try:
            with requests.get(url, stream=True, timeout=TIEMPO_ESPERA) as respuesta:
                respuesta.raise_for_status()
                escritos = 0
                with temporal.open("wb") as archivo:
                    for bloque in respuesta.iter_content(chunk_size=BLOQUE):
                        if bloque:
                            archivo.write(bloque)
                            escritos += len(bloque)
            if escritos != esperado:
                raise requests.RequestException(
                    f"descarga incompleta ({escritos} de {esperado} bytes)"
                )
            temporal.replace(destino)
            return escritos
        except requests.RequestException as error:
            ultimo_error = error
            temporal.unlink(missing_ok=True)
            if intento < INTENTOS:
                print(f"      intento {intento}/{INTENTOS} fallido ({error}); reintentando")

    raise requests.RequestException(f"no se pudo descargar {url}: {ultimo_error}")


def descargar(tipo: str, anio: int) -> dict:
    """Descarga todos los meses publicados de un tipo de taxi para un anio."""
    print(f"\n=== {tipo.upper()} {anio} ===")
    resumen = {"descargados": 0, "omitidos": 0, "no_publicados": [],
               "fallidos": [], "manifiesto": []}

    for mes in range(1, 13):
        etiqueta = f"{anio}-{mes:02d}"
        destino = ruta_destino(tipo, anio, mes)
        url = construir_url(tipo, anio, mes)
        local = destino.stat().st_size if destino.exists() else 0

        try:
            remoto = tamanio_remoto(url)
        except SinConexion as error:
            if local:
                print(f"  {etiqueta}  sin conexion, se conserva el archivo local")
                remoto = local
            else:
                print(f"  {etiqueta}  ERROR: {error}")
                resumen["fallidos"].append(etiqueta)
                continue

        if remoto is None:
            print(f"  {etiqueta}  aun no publicado por la TLC")
            resumen["no_publicados"].append(etiqueta)
            continue

        if local == remoto:
            print(f"  {etiqueta}  ya existe, se omite")
            estado = "existente"
        else:
            if local:
                print(f"  {etiqueta}  incompleto ({local} de {remoto} bytes), se descarga de nuevo")
            print(f"  {etiqueta}  descargando...")
            try:
                descargar_archivo(url, destino, remoto)
            except requests.RequestException as error:
                print(f"  {etiqueta}  ERROR: {error}")
                resumen["fallidos"].append(etiqueta)
                continue
            print(f"  {etiqueta}  listo ({formato_tamanio(remoto)}) -> {destino}")
            estado = "descargado"

        try:
            filas = filas_parquet(destino)
        except Exception as error:  # pyarrow lanza distintos tipos segun el dano
            print(f"  {etiqueta}  ERROR: Parquet ilegible ({error})")
            destino.unlink(missing_ok=True)
            resumen["fallidos"].append(etiqueta)
            continue

        resumen["descargados" if estado == "descargado" else "omitidos"] += 1
        resumen["manifiesto"].append({
            "tipo": tipo, "mes": etiqueta, "archivo": destino.as_posix(),
            "bytes": remoto, "filas": filas, "estado": estado,
        })

    return resumen


def descargar_zonas() -> bool:
    """Descarga la tabla de zonas si no existe localmente.

    El servidor la entrega comprimida (gzip) y sin Content-Length, asi que no
    se compara el tamanio: se valida que el CSV tenga el encabezado esperado.
    """
    print("\n=== ZONAS (taxi_zone_lookup.csv) ===")
    if ARCHIVO_ZONAS.exists():
        print("  ya existe, se omite")
        return True
    try:
        respuesta = requests.get(URL_ZONAS, timeout=TIEMPO_ESPERA)
        respuesta.raise_for_status()
    except requests.RequestException as error:
        print(f"  ERROR: {error}")
        return False
    if not respuesta.text.startswith('"LocationID","Borough","Zone","service_zone"'):
        print("  ERROR: el archivo no tiene el encabezado esperado")
        return False
    ARCHIVO_ZONAS.parent.mkdir(parents=True, exist_ok=True)
    ARCHIVO_ZONAS.write_bytes(respuesta.content)
    filas = respuesta.text.count("\n") - 1
    print(f"  listo ({filas} zonas) -> {ARCHIVO_ZONAS}")
    return True


def escribir_manifiesto(filas: list, tipos: tuple, anio: int) -> Path:
    """Reescribe el manifiesto del anio conservando las filas de tipos no procesados."""
    manifiesto = ruta_manifiesto(anio)
    if manifiesto.exists():
        with manifiesto.open(newline="") as archivo:
            filas = [f for f in csv.DictReader(archivo) if f["tipo"] not in tipos] + filas
    manifiesto.parent.mkdir(parents=True, exist_ok=True)
    with manifiesto.open("w", newline="") as archivo:
        escritor = csv.DictWriter(
            archivo, fieldnames=["tipo", "mes", "archivo", "bytes", "filas", "estado"]
        )
        escritor.writeheader()
        escritor.writerows(filas)
    return manifiesto


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Descarga los datos de taxis yellow y green del NYC TLC."
    )
    parser.add_argument(
        "--taxi", choices=(*TIPOS_TAXI, "all"), default="all",
        help="tipo de taxi a descargar (por defecto: all)",
    )
    parser.add_argument(
        "--anio", type=int, nargs="+", default=list(ANIOS),
        help=f"anios a descargar (por defecto: {' '.join(map(str, ANIOS))})",
    )
    argumentos = parser.parse_args()

    tipos = TIPOS_TAXI if argumentos.taxi == "all" else (argumentos.taxi,)
    anios = sorted(set(argumentos.anio))
    anio_actual = date.today().year
    invalidos = [a for a in anios if not PRIMER_ANIO_TLC <= a <= anio_actual]
    if invalidos:
        parser.error(f"anio fuera de rango ({PRIMER_ANIO_TLC}-{anio_actual}): {invalidos}")

    total = {"descargados": 0, "omitidos": 0, "no_publicados": [], "fallidos": []}
    filas_por_anio = {}
    manifiestos = []
    for anio in anios:
        manifiesto = []
        for tipo in tipos:
            resumen = descargar(tipo, anio)
            total["descargados"] += resumen["descargados"]
            total["omitidos"] += resumen["omitidos"]
            total["no_publicados"] += [f"{tipo} {m}" for m in resumen["no_publicados"]]
            total["fallidos"] += [f"{tipo} {m}" for m in resumen["fallidos"]]
            manifiesto += resumen["manifiesto"]
        manifiestos.append(escribir_manifiesto(manifiesto, tipos, anio))
        filas_por_anio[anio] = sum(f["filas"] for f in manifiesto)

    if not descargar_zonas():
        total["fallidos"].append("taxi_zone_lookup.csv")

    print("\n" + "=" * 60)
    print("RESUMEN")
    print("=" * 60)
    print(f"  descargados   : {total['descargados']}")
    print(f"  ya existian   : {total['omitidos']}")
    print(f"  no publicados : {len(total['no_publicados'])}")
    if total["no_publicados"]:
        print(f"      {', '.join(total['no_publicados'])}")
    print(f"  fallidos      : {len(total['fallidos'])}")
    if total["fallidos"]:
        print(f"      {', '.join(total['fallidos'])}")
    for anio, filas in filas_por_anio.items():
        print(f"  filas {anio}    : {filas:,}")
    print(f"  filas totales : {sum(filas_por_anio.values()):,}")
    print(f"  manifiestos   : {', '.join(m.as_posix() for m in manifiestos)}")
    print("=" * 60)

    return 1 if total["fallidos"] else 0


if __name__ == "__main__":
    sys.exit(main())
