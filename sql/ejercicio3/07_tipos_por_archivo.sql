-- 3.4 Tipos fisicos Parquet: columnas cuyo tipo o presencia cambia entre archivos
WITH esquema AS (
    SELECT regexp_extract(file_name, 'raw/(\w+)/', 1) AS tipo,
           regexp_extract(file_name, '(\d{4}-\d{2})\.parquet', 1) AS mes,
           name AS columna, type AS tipo_fisico, logical_type
    FROM parquet_schema('data/raw/*/2026/*.parquet')
    WHERE name <> 'schema'
)
SELECT tipo, columna,
       string_agg(DISTINCT tipo_fisico, ', ') AS tipos_fisicos,
       count(*) AS archivos_con_columna,
       string_agg(mes, ', ' ORDER BY mes) AS meses
FROM esquema
GROUP BY tipo, columna
HAVING count(DISTINCT tipo_fisico) > 1 OR count(*) < 8
ORDER BY tipo, columna;
