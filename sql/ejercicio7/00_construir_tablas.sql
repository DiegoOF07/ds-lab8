-- Tablas del tablero (data/processed/tablero.duckdb).
-- Se ejecuta después de sql/ejercicio4/00_vistas.sql, con la base adjunta como `t`
-- (ver scripts/construir_tablero.py). Se materializa porque el tablero repite las
-- mismas consultas (Ej. 6, 6.10).

-- viajes: viajes válidos según las reglas del Ej. 4, solo con las columnas que usan los indicadores.
CREATE OR REPLACE TABLE t.viajes AS
SELECT tipo,
       anio::SMALLINT AS anio,
       mes::TINYINT AS mes,
       pickup,
       dia_semana::TINYINT AS dia_semana,
       hora::TINYINT AS hora,
       PULocationID::SMALLINT AS origen_id,
       DOLocationID::SMALLINT AS destino_id,
       trip_distance AS distancia_mi,
       -- Redondeo a 2 decimales: sin él, estas dos columnas ocupaban un tercio de la base
       round(duracion_min, 2) AS duracion_min,
       -- Solo con duraciones de 1 min o más, como en el Ej. 4 (P4)
       CASE WHEN duracion_min >= 1 THEN round(trip_distance / (duracion_min / 60), 2) END AS velocidad_mph,
       payment_type::SMALLINT AS payment_type,
       forma_pago,
       fare_amount AS tarifa,
       tip_amount AS propina,
       total_amount AS total
FROM viajes_validos
-- Regla nueva: más de 80 mph es un error de captura (Ej. 4, P15)
WHERE duracion_min IS NULL
   OR duracion_min < 1
   OR trip_distance / (duracion_min / 60) <= 80;

-- viajes_comparables: solo los meses presentes en todos los años, para comparar años
-- sin mezclar estacionalidad con tendencia (mismo criterio que Ej. 5, consulta 06).
-- USE t hace que `viajes` se refiera a la tabla de esta base y no a la vista del Ej. 4.
USE t;
CREATE OR REPLACE VIEW viajes_comparables AS
SELECT *
FROM viajes
WHERE mes IN (
    SELECT mes FROM viajes
    GROUP BY mes
    HAVING count(DISTINCT anio) = (SELECT count(DISTINCT anio) FROM viajes)
);
USE memory;

CREATE OR REPLACE TABLE t.zonas AS
SELECT LocationID::SMALLINT AS zona_id, borough, zona, service_zone
FROM zonas;

-- calidad_mensual: registros descartados por cada regla, por tipo y mes.
CREATE OR REPLACE TABLE t.calidad_mensual AS
SELECT tipo,
       left(mes_archivo, 4)::SMALLINT AS anio,
       right(mes_archivo, 2)::TINYINT AS mes,
       count(*) AS registros,
       count(*) FILTER (WHERE NOT ok_fecha) AS fecha_fuera_del_mes,
       count(*) FILTER (WHERE NOT ok_duracion) AS duracion_invalida,
       count(*) FILTER (WHERE NOT ok_distancia) AS distancia_invalida,
       count(*) FILTER (WHERE NOT ok_monto) AS monto_negativo,
       count(*) FILTER (WHERE ok_fecha AND ok_duracion AND ok_distancia AND ok_monto
                          AND duracion_min >= 1 AND trip_distance / (duracion_min / 60) > 80)
           AS velocidad_imposible,
       count(*) FILTER (WHERE NOT (ok_fecha AND ok_duracion AND ok_distancia AND ok_monto)
                          OR (duracion_min >= 1 AND trip_distance / (duracion_min / 60) > 80))
           AS excluidos
FROM viajes
GROUP BY ALL;
