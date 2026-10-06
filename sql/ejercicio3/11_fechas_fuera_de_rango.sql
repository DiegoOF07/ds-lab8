-- 3.6 Viajes cuya fecha de inicio no corresponde al mes del archivo
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
       count(*) FILTER (WHERE strftime(pickup, '%Y-%m') <> mes_archivo) AS fuera_del_mes,
       count(*) FILTER (WHERE year(pickup) <> 2026) AS fuera_de_2026,
       min(pickup) AS pickup_min,
       max(pickup) AS pickup_max
FROM viajes
GROUP BY tipo
ORDER BY tipo;
