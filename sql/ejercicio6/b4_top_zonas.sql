-- B4. Las 10 zonas de origen con mas viajes por tipo (Ej. 4, P7)
-- Patron: join con una dimension pequena, agregacion y funcion de ventana.
SELECT v.tipo,
       row_number() OVER (PARTITION BY v.tipo ORDER BY count(*) DESC, z.zona) AS posicion,
       z.borough, z.zona,
       count(*) AS viajes
FROM {fuente} v
JOIN {zonas} z ON v.PULocationID = z.LocationID
GROUP BY v.tipo, z.borough, z.zona
QUALIFY posicion <= 10
ORDER BY v.tipo, posicion;
