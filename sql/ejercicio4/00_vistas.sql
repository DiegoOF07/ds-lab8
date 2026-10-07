-- 4.0 Vistas comunes para el analisis exploratorio
SET temp_directory = 'data/processed/duckdb_tmp';
SET max_temp_directory_size = '4GB';

-- viajes: yellow y green unidos, con columnas derivadas y una bandera por regla
-- de calidad. El glob '*/*.parquet' toma todos los anios en data/raw/<tipo>/.
CREATE OR REPLACE VIEW viajes AS
WITH base AS (
    SELECT 'yellow' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff, *
               EXCLUDE (tpep_pickup_datetime, tpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/yellow/*/*.parquet', filename = true, union_by_name = true)
    UNION ALL BY NAME
    SELECT 'green' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff, *
               EXCLUDE (lpep_pickup_datetime, lpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/green/*/*.parquet', filename = true, union_by_name = true)
)
SELECT * REPLACE (nullif(RatecodeID, 99) AS RatecodeID),   -- 99 = tarifa desconocida (Ej. 3, consulta 17)
       year(pickup) AS anio,
       month(pickup) AS mes,
       hour(pickup) AS hora,
       isodow(pickup) AS dia_semana,                         -- 1 = lunes ... 7 = domingo
       -- VendorID 7 (Helix) no registra la hora de bajada: dropoff = pickup en todos
       -- sus viajes (consulta 16). Su duracion se trata como faltante, no como cero.
       CASE WHEN VendorID = 7 AND dropoff = pickup THEN NULL
            ELSE epoch(dropoff - pickup) / 60 END AS duracion_min,
       CASE payment_type
           WHEN 0 THEN 'Flex Fare'
           WHEN 1 THEN 'Tarjeta'
           WHEN 2 THEN 'Efectivo'
           WHEN 3 THEN 'Sin cargo'
           WHEN 4 THEN 'Disputa'
           WHEN 5 THEN 'Desconocido'
           WHEN 6 THEN 'Anulado'
           ELSE 'Sin dato'
       END AS forma_pago,
       -- Reglas de calidad decididas en el Ejercicio 3 (consultas 11 a 13)
       strftime(pickup, '%Y-%m') = mes_archivo AS ok_fecha,
       (dropoff > pickup AND dropoff - pickup <= INTERVAL 24 HOUR)
           OR (VendorID = 7 AND dropoff = pickup) AS ok_duracion,
       trip_distance > 0 AND trip_distance <= 200 AS ok_distancia,
       fare_amount >= 0 AND total_amount >= 0 AS ok_monto
FROM base;

-- viajes_validos: solo los registros que cumplen las cuatro reglas.
CREATE OR REPLACE VIEW viajes_validos AS
SELECT *
FROM viajes
WHERE ok_fecha AND ok_duracion AND ok_distancia AND ok_monto;

-- zonas: tabla oficial de zonas de la TLC (descargada por scripts/download_data.py).
CREATE OR REPLACE VIEW zonas AS
SELECT LocationID, Borough AS borough, Zone AS zona, service_zone
FROM read_csv('data/raw/taxi_zone_lookup.csv', header = true);
