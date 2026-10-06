-- 3.6 Registros exactamente duplicados (todas las columnas iguales)
WITH yellow AS (
    SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
), green AS (
    SELECT * FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
)
SELECT 'yellow' AS tipo, count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM yellow)) AS filas_duplicadas
FROM yellow
UNION ALL
SELECT 'green', count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM green))
FROM green;
