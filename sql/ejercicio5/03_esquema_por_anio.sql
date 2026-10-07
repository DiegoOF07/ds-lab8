-- 5.5 Columnas cuya presencia o tipo cambia entre anios
-- Se compara el tipo fisico y el logico de cada columna en cada archivo.
WITH esquema AS (
    SELECT regexp_extract(file_name, 'raw/(\w+)/', 1) AS tipo,
           regexp_extract(file_name, '/(\d{4})/', 1) AS anio,
           name AS columna,
           type || coalesce(' ' || logical_type, '') AS tipo_columna
    FROM parquet_schema('data/raw/*/*/*.parquet')
    WHERE name <> 'schema'
), archivos AS (
    SELECT tipo, anio, count(DISTINCT file_name) AS total
    FROM (SELECT regexp_extract(file_name, 'raw/(\w+)/', 1) AS tipo,
                 regexp_extract(file_name, '/(\d{4})/', 1) AS anio, file_name
          FROM parquet_schema('data/raw/*/*/*.parquet'))
    GROUP BY ALL
), por_anio AS (
    SELECT e.tipo, e.columna, e.anio,
           string_agg(DISTINCT e.tipo_columna, ', ') AS tipos,
           count(*) AS archivos_con_columna,
           any_value(a.total) AS archivos_del_anio
    FROM esquema e
    JOIN archivos a USING (tipo, anio)
    GROUP BY ALL
)
SELECT tipo, columna,
       string_agg(anio || ': ' || archivos_con_columna || '/' || archivos_del_anio || ' archivos (' || tipos || ')',
                  ' | ' ORDER BY anio) AS detalle_por_anio
FROM por_anio
GROUP BY tipo, columna
HAVING count(DISTINCT tipos) > 1                                     -- cambia de tipo entre anios
    OR count(*) < (SELECT count(DISTINCT anio) FROM archivos)        -- falta en algun anio
    OR bool_or(archivos_con_columna < archivos_del_anio)             -- falta en algunos meses
ORDER BY tipo, columna;
