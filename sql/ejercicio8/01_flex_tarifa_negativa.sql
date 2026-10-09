-- Viajes Flex Fare de yellow con tarifa negativa, por mes
-- Objetivo: decidir si son viajes reales (distancia normal) o registros inválidos.
SELECT anio, mes,
       count(*) AS flex_fare,
       count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa,
       round(100 * count(*) FILTER (WHERE fare_amount < 0) / count(*), 1) AS pct_tarifa_negativa,
       round(100 * count(*) FILTER (WHERE fare_amount < 0 AND VendorID = 2)
             / nullif(count(*) FILTER (WHERE fare_amount < 0), 0), 1) AS pct_vendor2,
       round(median(trip_distance) FILTER (WHERE fare_amount < 0), 2) AS distancia_negativa,
       round(median(trip_distance) FILTER (WHERE fare_amount >= 0), 2) AS distancia_resto,
       round(median(total_amount) FILTER (WHERE fare_amount < 0), 2) AS total_negativa,
       round(median(total_amount) FILTER (WHERE fare_amount >= 0), 2) AS total_resto
FROM viajes
WHERE tipo = 'yellow' AND payment_type = 0
GROUP BY anio, mes
ORDER BY anio, mes;
