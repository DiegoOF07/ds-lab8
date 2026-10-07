-- P7. Las 10 zonas de origen con mas viajes por tipo de taxi
SELECT v.tipo,
       row_number() OVER (PARTITION BY v.tipo ORDER BY count(*) DESC) AS posicion,
       z.borough, z.zona, z.service_zone,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo), 2) AS pct_del_tipo
FROM viajes_validos v
JOIN zonas z ON v.PULocationID = z.LocationID
GROUP BY v.tipo, z.borough, z.zona, z.service_zone
QUALIFY posicion <= 10
ORDER BY v.tipo, posicion;
