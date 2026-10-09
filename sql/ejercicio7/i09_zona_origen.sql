-- I9. Zona de origen
-- Pregunta: ¿dónde opera cada servicio y se mantiene su separación?
SELECT v.tipo || ' ' || v.anio AS grupo,
       CASE WHEN z.service_zone = 'Yellow Zone' THEN 'Manhattan centro (Yellow Zone)'
            WHEN z.service_zone = 'Boro Zone' AND z.borough = 'Manhattan' THEN 'Alto Manhattan'
            WHEN z.service_zone = 'Boro Zone' AND z.borough IN ('Brooklyn', 'Queens') THEN z.borough
            -- aeropuertos (ver I8), Bronx, Staten Island y zonas desconocidas
            ELSE 'Resto' END AS origen,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo, v.anio), 2) AS pct_viajes
FROM viajes_comparables v
JOIN zonas z ON v.origen_id = z.zona_id
GROUP BY v.tipo, v.anio, origen
ORDER BY v.tipo DESC, v.anio,
         list_position(['Manhattan centro (Yellow Zone)', 'Alto Manhattan', 'Brooklyn', 'Queens', 'Resto'], origen);
