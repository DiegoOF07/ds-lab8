-- 6.1 Vista sobre los archivos Parquet de una escala del benchmark
-- Plantilla: scripts/benchmark.py reemplaza {vista}, {glob_yellow} y {glob_green}.
-- Es la misma union que la vista base del Ejercicio 4, sin columnas derivadas,
-- para que la tabla materializada (01_crear_tabla.sql) tenga exactamente las mismas filas.
CREATE OR REPLACE VIEW {vista} AS
SELECT 'yellow' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
       tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff, *
           EXCLUDE (tpep_pickup_datetime, tpep_dropoff_datetime, filename)
FROM read_parquet('{glob_yellow}', filename = true, union_by_name = true)
UNION ALL BY NAME
SELECT 'green' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
       lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff, *
           EXCLUDE (lpep_pickup_datetime, lpep_dropoff_datetime, filename)
FROM read_parquet('{glob_green}', filename = true, union_by_name = true);
