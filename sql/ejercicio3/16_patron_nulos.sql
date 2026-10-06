-- 3.6 Perfil de los registros con passenger_count nulo: ¿se concentran en algun proveedor o forma de pago?
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
SELECT tipo, VendorID, payment_type, RatecodeID,
       count(*) AS registros,
       count(*) FILTER (WHERE store_and_fwd_flag IS NULL AND congestion_surcharge IS NULL) AS tambien_nulos
FROM viajes
WHERE passenger_count IS NULL
GROUP BY ALL
ORDER BY registros DESC
LIMIT 10;
