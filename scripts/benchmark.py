#!/usr/bin/env python3
"""Benchmark del Ejercicio 6: consultas sobre Parquet frente a tablas DuckDB.

Para cada escala de datos:
  1. crea una vista sobre los Parquet (sql/ejercicio6/00_fuente_parquet.sql);
  2. materializa las mismas filas como tabla en data/processed/taxis.duckdb
     (sql/ejercicio6/01_crear_tabla.sql) y registra el tiempo y el tamanio;
  3. ejecuta las consultas sql/ejercicio6/b*.sql contra ambas fuentes. Cada
     consulta se escribe una sola vez con el marcador {fuente}, asi que lo unico
     que cambia entre estrategias es el FROM;
  4. comprueba que ambas estrategias devuelven el mismo resultado.

Cada combinacion (escala, estrategia, consulta) usa una conexion nueva. Se mide
la primera ejecucion y luego `--repeticiones` ejecuciones adicionales, de las
que se reporta la mediana, el minimo y el maximo. Los tiempos se toman con
time.perf_counter(), que es monotono (el reloj del contenedor da saltos).

Uso:
    python scripts/benchmark.py                      # materializa lo que falte y mide
    python scripts/benchmark.py --recrear            # vuelve a crear las tablas
    python scripts/benchmark.py --repeticiones 3

Salidas:
    data/processed/taxis.duckdb            tablas materializadas (no se versiona)
    docs/ejercicio6_materializacion.csv    tiempo y tamanio de cada tabla
    docs/ejercicio6_benchmark.csv          tiempos de cada consulta
"""

import argparse
import csv
import glob
import os
import statistics
import sys
import time
from pathlib import Path

import duckdb
import pandas as pd

DIR_SQL = Path("sql/ejercicio6")
BASE_DATOS = Path("data/processed/taxis.duckdb")
ARCHIVO_ZONAS = "data/raw/taxi_zone_lookup.csv"
SALIDA_MATERIALIZACION = Path("docs/ejercicio6_materializacion.csv")
SALIDA_BENCHMARK = Path("docs/ejercicio6_benchmark.csv")

# Escalas de datos: de un mes a todos los anios descargados
ESCALAS = [
    {"escala": "1 mes (2026-01)", "tabla": "viajes_2026_01",
     "yellow": "data/raw/yellow/2026/yellow_tripdata_2026-01.parquet",
     "green": "data/raw/green/2026/green_tripdata_2026-01.parquet"},
    {"escala": "2026 (8 meses)", "tabla": "viajes_2026",
     "yellow": "data/raw/yellow/2026/*.parquet",
     "green": "data/raw/green/2026/*.parquet"},
    {"escala": "todos los anios", "tabla": "viajes",
     "yellow": "data/raw/yellow/*/*.parquet",
     "green": "data/raw/green/*/*.parquet"},
]


def configurar(con: duckdb.DuckDBPyConnection) -> None:
    """Misma configuracion para ambas estrategias; temporales acotados (ver Ej. 5)."""
    con.execute("SET temp_directory = 'data/processed/duckdb_tmp'")
    con.execute("SET max_temp_directory_size = '4GB'")


def rellenar(sql: str, **valores) -> str:
    """Reemplaza los marcadores {nombre}. No usa str.format porque las
    expresiones regulares del SQL (p. ej. \\d{4}) tambien llevan llaves."""
    for clave, valor in valores.items():
        sql = sql.replace("{" + clave + "}", valor)
    return sql


def plantilla(nombre: str, **valores) -> str:
    return rellenar((DIR_SQL / nombre).read_text(), **valores)


def vista_parquet(escala: dict) -> str:
    return f"parquet_{escala['tabla']}"


def crear_vista(con: duckdb.DuckDBPyConnection, escala: dict) -> None:
    con.execute(plantilla("00_fuente_parquet.sql", vista=vista_parquet(escala),
                          glob_yellow=escala["yellow"], glob_green=escala["green"]))


def bytes_parquet(escala: dict) -> int:
    archivos = glob.glob(escala["yellow"]) + glob.glob(escala["green"])
    return sum(os.path.getsize(a) for a in archivos)


def materializar(recrear: bool) -> None:
    """Crea las tablas que falten (o todas con --recrear) y registra su costo."""
    BASE_DATOS.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    configurar(con)
    con.execute(f"ATTACH '{BASE_DATOS}' AS db")
    existentes = {fila[0] for fila in con.execute(
        "SELECT table_name FROM duckdb_tables() WHERE database_name = 'db'").fetchall()}

    con.execute(f"""CREATE OR REPLACE TABLE db.zonas AS
                    SELECT LocationID, Borough AS borough, Zone AS zona, service_zone
                    FROM read_csv('{ARCHIVO_ZONAS}', header = true)""")

    registros = []
    for escala in ESCALAS:
        if escala["tabla"] in existentes and not recrear:
            print(f"  {escala['tabla']:<16} ya existe, se omite")
            continue
        crear_vista(con, escala)
        con.execute("CHECKPOINT db")
        antes = BASE_DATOS.stat().st_size
        inicio = time.perf_counter()
        con.execute(plantilla("01_crear_tabla.sql", tabla=f"db.{escala['tabla']}",
                              vista=vista_parquet(escala)))
        con.execute("CHECKPOINT db")
        segundos = time.perf_counter() - inicio
        filas = con.execute(f"SELECT count(*) FROM db.{escala['tabla']}").fetchone()[0]
        crecimiento = BASE_DATOS.stat().st_size - antes
        print(f"  {escala['tabla']:<16} {filas:>12,} filas en {segundos:6.1f} s "
              f"({crecimiento / 2**20:,.0f} MiB)")
        registros.append({
            "escala": escala["escala"], "tabla": escala["tabla"], "filas": filas,
            "segundos_creacion": round(segundos, 2),
            "mib_parquet": round(bytes_parquet(escala) / 2**20, 1),
            "mib_tabla_duckdb": round(crecimiento / 2**20, 1),
        })
    con.close()

    if registros:
        # Conserva las filas de las tablas que no se recrearon en esta ejecucion
        previos = []
        if SALIDA_MATERIALIZACION.exists() and not recrear:
            previos = pd.read_csv(SALIDA_MATERIALIZACION).to_dict("records")
        nuevas = {r["tabla"] for r in registros}
        filas = [p for p in previos if p["tabla"] not in nuevas] + registros
        orden = [e["tabla"] for e in ESCALAS]
        filas.sort(key=lambda r: orden.index(r["tabla"]))
        pd.DataFrame(filas).to_csv(SALIDA_MATERIALIZACION, index=False)


def conectar(escala: dict) -> duckdb.DuckDBPyConnection:
    """Conexion nueva con la vista Parquet y la base materializada en solo lectura."""
    con = duckdb.connect()
    configurar(con)
    con.execute(f"ATTACH '{BASE_DATOS}' AS db (READ_ONLY)")
    crear_vista(con, escala)
    con.execute(f"""CREATE VIEW zonas_csv AS
                    SELECT LocationID, Borough AS borough, Zone AS zona, service_zone
                    FROM read_csv('{ARCHIVO_ZONAS}', header = true)""")
    return con


def medir(con: duckdb.DuckDBPyConnection, sql: str) -> tuple[float, pd.DataFrame]:
    inicio = time.perf_counter()
    resultado = con.sql(sql).df()
    return time.perf_counter() - inicio, resultado


def mismos_resultados(a: pd.DataFrame, b: pd.DataFrame) -> bool:
    """Compara dos resultados tolerando diferencias de redondeo en sumas de punto flotante."""
    if list(a.columns) != list(b.columns) or len(a) != len(b):
        return False
    for columna in a.columns:
        x, y = a[columna].reset_index(drop=True), b[columna].reset_index(drop=True)
        if pd.api.types.is_float_dtype(x):
            if not ((x - y).abs() <= 0.011 + 1e-9 * y.abs()).all():
                return False
        elif not x.astype(str).equals(y.astype(str)):
            return False
    return True


def benchmark(repeticiones: int) -> None:
    consultas = sorted(DIR_SQL.glob("b*.sql"))
    filas = []
    for escala in ESCALAS:
        print(f"\n=== {escala['escala']} ===")
        for archivo in consultas:
            resultados = {}
            for estrategia in ("parquet", "tabla"):
                fuente = vista_parquet(escala) if estrategia == "parquet" else f"db.{escala['tabla']}"
                zonas = "zonas_csv" if estrategia == "parquet" else "db.zonas"
                sql = rellenar(archivo.read_text(), fuente=fuente, zonas=zonas)
                con = conectar(escala)
                primera, resultados[estrategia] = medir(con, sql)
                tiempos = [medir(con, sql)[0] for _ in range(repeticiones)]
                con.close()
                filas.append({
                    "escala": escala["escala"], "consulta": archivo.stem, "estrategia": estrategia,
                    "primera_s": round(primera, 4),
                    "mediana_s": round(statistics.median(tiempos), 4),
                    "min_s": round(min(tiempos), 4), "max_s": round(max(tiempos), 4),
                    "repeticiones": repeticiones,
                })
                print(f"  {archivo.stem:<26} {estrategia:<8} primera {primera:7.3f} s   "
                      f"mediana {statistics.median(tiempos):7.3f} s")
            iguales = mismos_resultados(resultados["parquet"], resultados["tabla"])
            for fila in filas[-2:]:
                fila["resultado_igual"] = iguales
            if not iguales:
                print(f"  ATENCION: {archivo.stem} da resultados distintos en {escala['escala']}")

    with SALIDA_BENCHMARK.open("w", newline="") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=list(filas[0]))
        escritor.writeheader()
        escritor.writerows(filas)
    print(f"\nResultados en {SALIDA_BENCHMARK}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark Parquet frente a tablas DuckDB.")
    parser.add_argument("--repeticiones", type=int, default=5,
                        help="ejecuciones medidas despues de la primera (por defecto: 5)")
    parser.add_argument("--recrear", action="store_true",
                        help="vuelve a crear las tablas aunque ya existan")
    argumentos = parser.parse_args()

    print("=== Materializacion ===")
    materializar(argumentos.recrear)
    benchmark(argumentos.repeticiones)
    return 0


if __name__ == "__main__":
    sys.exit(main())
