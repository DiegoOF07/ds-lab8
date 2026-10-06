#!/usr/bin/env python3
"""Descarga los archivos Parquet de 2026 del NYC TLC Trip Record Data.

Descarga los registros de viajes de taxis amarillos (yellow) y verdes (green)
correspondientes al anio 2026, que es el conjunto de datos inicial del
laboratorio. Este script solo contempla el anio 2026.

Fuente oficial de los datos:
    https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page

Uso:
    python scripts/download_data.py                 # amarillos y verdes
    python scripts/download_data.py --taxi yellow
    python scripts/download_data.py --taxi green

Los archivos se guardan en:
    data/raw/<tipo>/<anio>/<nombre-original>.parquet

Comportamiento:
  - La TLC publica cada mes con varias semanas de atraso, por lo que no todos
    los meses de 2026 existen todavia. El script consulta al servidor que
    meses estan publicados en lugar de suponerlos.
  - Un archivo que ya existe localmente no se vuelve a descargar, siempre que
    su tamanio coincida con el publicado (Content-Length). Si difiere se
    considera incompleto y se descarga de nuevo.
  - Cada archivo se valida leyendo su metadata Parquet (cantidad de filas).
  - Al terminar se escribe data/raw/manifest_<anio>.csv con el detalle de
    cada archivo, que sirve para verificar que la descarga esta completa.
  - La descarga se hace sobre un nombre temporal y solo se renombra al
    terminar, de modo que una interrupcion no deja archivos .parquet a medias.
"""

import argparse
import csv
import sys
from pathlib import Path

import pyarrow.parquet as pq
import requests

ANIO = 2026
TIPOS_TAXI = ("yellow", "green")
URL_BASE = "https://d37ci6vzurychx.cloudfront.net/trip-data"
DIR_DESTINO = Path("data/raw")
MANIFIESTO = DIR_DESTINO / f"manifest_{ANIO}.csv"

TIEMPO_ESPERA = 60          # segundos por peticion
INTENTOS = 3                # intentos por archivo antes de darse por vencido
BLOQUE = 1024 * 1024        # 1 MiB por bloque de descarga
SUFIJO_TEMPORAL = ".part"


def construir_nombre(tipo: str, mes: int) -> str:
    """Nombre del archivo publicado por la TLC, p. ej. yellow_tripdata_2026-01.parquet."""
    return f"{tipo}_tripdata_{ANIO}-{mes:02d}.parquet"


def construir_url(tipo: str, mes: int) -> str:
    """URL completa del archivo Parquet mensual."""
    return f"{URL_BASE}/{construir_nombre(tipo, mes)}"


def ruta_destino(tipo: str, mes: int) -> Path:
    """Ruta local donde se guarda el archivo."""
    return DIR_DESTINO / tipo / str(ANIO) / construir_nombre(tipo, mes)


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


def descargar(tipo: str) -> dict:
    """Descarga todos los meses publicados de un tipo de taxi para 2026."""
    print(f"\n=== {tipo.upper()} {ANIO} ===")
    resumen = {"descargados": 0, "omitidos": 0, "no_publicados": [],
               "fallidos": [], "manifiesto": []}

    for mes in range(1, 13):
        etiqueta = f"{ANIO}-{mes:02d}"
        destino = ruta_destino(tipo, mes)
        url = construir_url(tipo, mes)
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


def escribir_manifiesto(filas: list, tipos: tuple) -> None:
    """Reescribe el manifiesto conservando las filas de tipos no procesados."""
    if MANIFIESTO.exists():
        with MANIFIESTO.open(newline="") as archivo:
            filas = [f for f in csv.DictReader(archivo) if f["tipo"] not in tipos] + filas
    MANIFIESTO.parent.mkdir(parents=True, exist_ok=True)
    with MANIFIESTO.open("w", newline="") as archivo:
        escritor = csv.DictWriter(
            archivo, fieldnames=["tipo", "mes", "archivo", "bytes", "filas", "estado"]
        )
        escritor.writeheader()
        escritor.writerows(filas)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=f"Descarga los datos de taxis de {ANIO} del NYC TLC."
    )
    parser.add_argument(
        "--taxi", choices=(*TIPOS_TAXI, "all"), default="all",
        help="tipo de taxi a descargar (por defecto: all)",
    )
    argumentos = parser.parse_args()

    tipos = TIPOS_TAXI if argumentos.taxi == "all" else (argumentos.taxi,)

    total = {"descargados": 0, "omitidos": 0, "no_publicados": [], "fallidos": []}
    manifiesto = []
    for tipo in tipos:
        resumen = descargar(tipo)
        total["descargados"] += resumen["descargados"]
        total["omitidos"] += resumen["omitidos"]
        total["no_publicados"] += [f"{tipo} {m}" for m in resumen["no_publicados"]]
        total["fallidos"] += [f"{tipo} {m}" for m in resumen["fallidos"]]
        manifiesto += resumen["manifiesto"]

    escribir_manifiesto(manifiesto, tipos)

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
    print(f"  filas totales : {sum(f['filas'] for f in manifiesto):,}")
    print(f"  manifiesto    : {MANIFIESTO}")
    print("=" * 60)

    return 1 if total["fallidos"] else 0


if __name__ == "__main__":
    sys.exit(main())
