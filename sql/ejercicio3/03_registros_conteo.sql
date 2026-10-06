-- 3.2 Registros por tipo contando filas (contraste con la metadata)
SELECT regexp_extract(filename, 'raw/(\w+)/', 1) AS tipo,
       count(*) AS registros
FROM read_parquet('data/raw/*/2026/*.parquet', filename = true, union_by_name = true)
GROUP BY ALL
UNION ALL
SELECT 'TOTAL', count(*)
FROM read_parquet('data/raw/*/2026/*.parquet', union_by_name = true)
ORDER BY tipo;
