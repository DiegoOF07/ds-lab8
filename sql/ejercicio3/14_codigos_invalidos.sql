-- 3.6 Valores fuera del diccionario de datos de la TLC
WITH viajes AS (
    SELECT 'yellow' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff, *
               EXCLUDE (tpep_pickup_datetime, tpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/yellow/2026/*.parquet', filename = true, union_by_name = true)
    UNION ALL BY NAME
    SELECT 'green' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff, *
               EXCLUDE (lpep_pickup_datetime, lpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/green/2026/*.parquet', filename = true, union_by_name = true)
)
SELECT tipo,
       count(*) FILTER (WHERE passenger_count = 0) AS pasajeros_cero,
       count(*) FILTER (WHERE passenger_count > 6) AS pasajeros_mas_de_6,
       count(*) FILTER (WHERE RatecodeID NOT BETWEEN 1 AND 6) AS ratecode_fuera_dic,
       count(*) FILTER (WHERE payment_type NOT BETWEEN 0 AND 6) AS payment_fuera_dic,
       count(*) FILTER (WHERE payment_type = 0) AS payment_cero,
       count(*) FILTER (WHERE PULocationID NOT BETWEEN 1 AND 263
                           OR DOLocationID NOT BETWEEN 1 AND 263) AS zona_desconocida,
       list_sort(list(DISTINCT VendorID)) AS vendor_ids
FROM viajes
GROUP BY tipo
ORDER BY tipo;
