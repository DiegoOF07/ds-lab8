#!/usr/bin/env python3
"""Ejercicio 9.4: memoria de cargar los datos en pandas frente a consultarlos con DuckDB.

Carga un mes de yellow en un DataFrame, mide su memoria y la extrapola a todos los
archivos de data/raw/. Luego ejecuta con DuckDB una agregación sobre todos los
archivos y mide su tiempo.
"""

import glob
import time

import duckdb
import pandas as pd
import pyarrow.parquet as pq

MES = "data/raw/yellow/2025/yellow_tripdata_2025-05.parquet"
ARCHIVOS = sorted(glob.glob("data/raw/*/*/*.parquet"))

inicio = time.perf_counter()
df = pd.read_parquet(MES)
segundos_pandas = time.perf_counter() - inicio
bytes_df = df.memory_usage(deep=True).sum()
filas_totales = sum(pq.read_metadata(a).num_rows for a in ARCHIVOS)
estimado = bytes_df / len(df) * filas_totales
del df

con = duckdb.connect()
con.execute("SET enable_progress_bar = false")
inicio = time.perf_counter()
grupos = con.sql("""
    SELECT regexp_extract(filename, '/(\\d{4})/', 1) AS anio, count(*), avg(total_amount)
    FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
    GROUP BY anio
""").fetchall()
segundos_duckdb = time.perf_counter() - inicio

print(f"pandas, un mes ({MES.rsplit('/', 1)[1]}): {bytes_df / 2**30:.2f} GiB en memoria, "
      f"{segundos_pandas:.1f} s")
print(f"pandas, {len(ARCHIVOS)} archivos ({filas_totales:,} filas), estimado: "
      f"{estimado / 2**30:.1f} GiB")
print(f"DuckDB, conteo y promedio por año sobre los {len(ARCHIVOS)} archivos: "
      f"{segundos_duckdb:.1f} s, {len(grupos)} filas de resultado")
