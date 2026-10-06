-- 3.3 Columnas presentes en cada tipo de taxi y en cuantos archivos aparecen
SELECT name AS columna,
       count(DISTINCT file_name) FILTER (WHERE file_name LIKE '%/yellow/%') AS archivos_yellow,
       count(DISTINCT file_name) FILTER (WHERE file_name LIKE '%/green/%') AS archivos_green
FROM parquet_schema('data/raw/*/2026/*.parquet')
WHERE name <> 'schema'
GROUP BY name
ORDER BY archivos_yellow = 0, archivos_green = 0, columna;
