-- 3.6 Distribucion de RatecodeID y payment_type para entender los codigos fuera del diccionario
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
SELECT tipo, 'RatecodeID' AS columna, RatecodeID AS valor, count(*) AS registros
FROM viajes GROUP BY ALL
UNION ALL
SELECT tipo, 'payment_type', payment_type, count(*)
FROM viajes GROUP BY ALL
ORDER BY tipo, columna, valor NULLS LAST;
