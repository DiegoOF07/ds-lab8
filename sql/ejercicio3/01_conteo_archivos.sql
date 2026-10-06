-- 3.1 Cantidad de archivos Parquet disponibles por tipo de taxi
SELECT regexp_extract(file, 'raw/(\w+)/', 1) AS tipo,
       count(*) AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS ultimo_mes
FROM glob('data/raw/*/2026/*.parquet')
GROUP BY ALL
ORDER BY tipo;
