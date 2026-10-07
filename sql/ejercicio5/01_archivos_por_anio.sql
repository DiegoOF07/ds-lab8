-- 5.5 Archivos disponibles por tipo y anio, y rango de meses que cubren
SELECT regexp_extract(file, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(file, '/(\d{4})/', 1)::INT AS anio,
       count(*) AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS ultimo_mes
FROM glob('data/raw/*/*/*.parquet')
GROUP BY ALL
ORDER BY anio, tipo;
