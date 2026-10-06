-- 3.6 Duraciones imposibles o sospechosas
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
       count(*) FILTER (WHERE dropoff < pickup) AS dropoff_antes_pickup,
       count(*) FILTER (WHERE dropoff = pickup) AS duracion_cero,
       count(*) FILTER (WHERE dropoff - pickup > INTERVAL 24 HOUR) AS mas_de_24h,
       max(dropoff - pickup) AS duracion_max
FROM viajes
GROUP BY tipo
ORDER BY tipo;
