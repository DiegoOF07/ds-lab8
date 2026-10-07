-- P6. Donde se originan los viajes de cada tipo: borough y zona de servicio
SELECT v.tipo, z.borough, z.service_zone,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo), 2) AS pct_del_tipo
FROM viajes_validos v
JOIN zonas z ON v.PULocationID = z.LocationID
GROUP BY v.tipo, z.borough, z.service_zone
ORDER BY v.tipo, viajes DESC;
