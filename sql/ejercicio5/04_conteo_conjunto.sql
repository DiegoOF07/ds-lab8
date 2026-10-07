-- 5.6 Conteo conjunto de 2024 y 2026 leyendo todos los Parquet con un solo glob
SELECT regexp_extract(filename, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(filename, '/(\d{4})/', 1)::INT AS anio,
       count(DISTINCT filename) AS archivos,
       count(*) AS registros
FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
GROUP BY ALL
ORDER BY anio, tipo;
