-- 3.6 Distancias y montos fuera de lo razonable
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
       count(*) FILTER (WHERE trip_distance = 0) AS distancia_cero,
       count(*) FILTER (WHERE trip_distance > 200) AS distancia_mayor_200mi,
       max(trip_distance) AS distancia_max,
       count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa,
       count(*) FILTER (WHERE total_amount < 0) AS total_negativo,
       count(*) FILTER (WHERE total_amount > 1000) AS total_mayor_1000,
       min(total_amount) AS total_min,
       max(total_amount) AS total_max
FROM viajes
GROUP BY tipo
ORDER BY tipo;
