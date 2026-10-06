-- 3.2 Registros por archivo leidos del footer Parquet (sin escanear los datos)
SELECT regexp_extract(file_name, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(file_name, '(\d{4}-\d{2})\.parquet', 1) AS mes,
       num_rows AS registros,
       num_row_groups AS row_groups
FROM parquet_file_metadata('data/raw/*/2026/*.parquet')
ORDER BY tipo, mes;
