-- 5.5 Contraste entre los manifiestos del script de descarga y la metadata de los Parquet
-- Un archivo que aparece solo en un lado, o con distinta cantidad de filas, es un error.
WITH manifiesto AS (
    SELECT archivo, tipo, filas
    FROM read_csv('data/raw/manifest_*.csv', header = true)
), metadata AS (
    SELECT file_name AS archivo, num_rows AS filas
    FROM parquet_file_metadata('data/raw/*/*/*.parquet')
)
SELECT coalesce(m.tipo, regexp_extract(p.archivo, 'raw/(\w+)/', 1)) AS tipo,
       regexp_extract(coalesce(m.archivo, p.archivo), '/(\d{4})/', 1)::INT AS anio,
       count(m.archivo) AS archivos_manifiesto,
       count(p.archivo) AS archivos_en_disco,
       sum(m.filas) AS filas_manifiesto,
       sum(p.filas) AS filas_metadata,
       count(*) FILTER (WHERE m.archivo IS NULL OR p.archivo IS NULL OR m.filas <> p.filas) AS diferencias
FROM manifiesto m
FULL OUTER JOIN metadata p USING (archivo)
GROUP BY ALL
ORDER BY anio, tipo;
