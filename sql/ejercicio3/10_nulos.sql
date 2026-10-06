-- 3.6 Porcentaje de nulos por columna y tipo de taxi
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
SELECT tipo, count(*) AS registros,
       round(100 * count(*) FILTER (WHERE passenger_count IS NULL) / count(*), 2) AS pct_null_passenger_count,
       round(100 * count(*) FILTER (WHERE RatecodeID IS NULL) / count(*), 2) AS pct_null_ratecodeid,
       round(100 * count(*) FILTER (WHERE store_and_fwd_flag IS NULL) / count(*), 2) AS pct_null_store_and_fwd,
       round(100 * count(*) FILTER (WHERE congestion_surcharge IS NULL) / count(*), 2) AS pct_null_congestion,
       round(100 * count(*) FILTER (WHERE payment_type IS NULL) / count(*), 2) AS pct_null_payment_type,
       round(100 * count(*) FILTER (WHERE trip_type IS NULL) / count(*), 2) AS pct_null_trip_type,
       round(100 * count(*) FILTER (WHERE ehail_fee IS NULL) / count(*), 2) AS pct_null_ehail_fee,
       round(100 * count(*) FILTER (WHERE request_source IS NULL) / count(*), 2) AS pct_null_request_source
FROM viajes
GROUP BY tipo
ORDER BY tipo;
