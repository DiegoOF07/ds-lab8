-- 6.2 Materializa una escala del benchmark como tabla en data/processed/taxis.duckdb
-- Plantilla: scripts/benchmark.py reemplaza {tabla} y {vista}.
-- Se copian las filas tal como estan en los Parquet (sin limpieza ni cambios de tipo):
-- el benchmark compara estrategias de acceso, no transformaciones.
CREATE OR REPLACE TABLE {tabla} AS
SELECT * FROM {vista};
