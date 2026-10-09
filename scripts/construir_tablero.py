#!/usr/bin/env python3
"""Construye la base del tablero del Ejercicio 7 (data/processed/tablero.duckdb).

Crea las vistas del Ejercicio 4, materializa las tablas de
sql/ejercicio7/00_construir_tablas.sql, verifica que las filas cuadren con el
control de calidad y ejecuta cada indicador (sql/ejercicio7/i*.sql).

La base se escribe en un archivo temporal que luego reemplaza a la anterior.
Metabase sigue leyendo la versión anterior hasta que se reinicia
(docker compose restart metabase).
"""

import os
import sys
import time
from pathlib import Path

import duckdb

DIR_SQL = Path("sql/ejercicio7")
VISTAS = Path("sql/ejercicio4/00_vistas.sql")
BASE_DATOS = Path("data/processed/tablero.duckdb")
TEMPORAL = BASE_DATOS.with_name(BASE_DATOS.name + ".tmp")


def construir() -> None:
    BASE_DATOS.parent.mkdir(parents=True, exist_ok=True)
    TEMPORAL.unlink(missing_ok=True)
    con = duckdb.connect()
    con.execute("SET enable_progress_bar = false")
    con.execute(VISTAS.read_text())
    con.execute(f"ATTACH '{TEMPORAL}' AS t")

    inicio = time.perf_counter()
    con.execute((DIR_SQL / "00_construir_tablas.sql").read_text())
    con.execute("CHECKPOINT t")
    print(f"tablas creadas en {time.perf_counter() - inicio:.1f} s")

    # Registros de los Parquet menos excluidos debe ser igual a las filas de viajes
    resumen = con.sql("""
        SELECT v.tipo, v.anio, v.viajes, c.registros, c.excluidos
        FROM (SELECT tipo, anio, count(*) AS viajes FROM t.viajes GROUP BY ALL) v
        JOIN (SELECT tipo, anio, sum(registros) AS registros, sum(excluidos) AS excluidos
              FROM t.calidad_mensual GROUP BY ALL) c USING (tipo, anio)
        ORDER BY v.anio, v.tipo
    """).fetchall()
    print(f"\n{'tipo':<8}{'año':>6}{'registros':>14}{'excluidos':>12}{'viajes':>14}")
    descuadre = False
    for tipo, anio, viajes, registros, excluidos in resumen:
        print(f"{tipo:<8}{anio:>6}{registros:>14,}{excluidos:>12,}{viajes:>14,}")
        descuadre |= registros - excluidos != viajes
    con.close()
    if descuadre:
        raise SystemExit("ERROR: registros - excluidos no coincide con las filas de t.viajes")

    try:
        os.replace(TEMPORAL, BASE_DATOS)
    except OSError as error:
        raise SystemExit(f"ERROR: no se pudo reemplazar {BASE_DATOS} ({error}). "
                         "Detenga Metabase (docker compose stop metabase) y vuelva a ejecutar.")
    print(f"\nbase escrita en {BASE_DATOS} ({BASE_DATOS.stat().st_size / 2**20:,.0f} MiB)")


def probar_indicadores() -> None:
    con = duckdb.connect(str(BASE_DATOS), read_only=True)
    con.execute("SET enable_progress_bar = false")
    print()
    for archivo in sorted(DIR_SQL.glob("i*.sql")):
        inicio = time.perf_counter()
        filas = len(con.sql(archivo.read_text()).fetchall())
        print(f"  {archivo.stem:<32} {filas:>5} filas  {time.perf_counter() - inicio:6.2f} s")
    con.close()


def main() -> int:
    construir()
    probar_indicadores()
    return 0


if __name__ == "__main__":
    sys.exit(main())
