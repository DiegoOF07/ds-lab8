-- P16. Que proveedores generan los viajes con duracion cero (dropoff = pickup)?
-- Se consulta la vista viajes (sin filtrar) para ver todos los registros.
SELECT tipo, VendorID,
       count(*) AS registros,
       count(*) FILTER (WHERE dropoff = pickup) AS duracion_cero,
       round(100 * count(*) FILTER (WHERE dropoff = pickup) / count(*), 2) AS pct_duracion_cero,
       round(100 * count(*) FILTER (WHERE dropoff = pickup) / sum(count(*) FILTER (WHERE dropoff = pickup)) OVER (PARTITION BY tipo), 2) AS pct_del_total_cero,
       round(median(trip_distance) FILTER (WHERE dropoff = pickup), 2) AS distancia_mediana_cero,
       round(median(fare_amount) FILTER (WHERE dropoff = pickup), 2) AS tarifa_mediana_cero
FROM viajes
GROUP BY tipo, VendorID
ORDER BY tipo, VendorID;
