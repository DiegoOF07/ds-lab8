-- I4. Velocidad mediana por hora en el centro de Manhattan (yellow, días laborales)
-- Pregunta: ¿cómo cambia la congestión durante el día y entre años?
-- Origen y destino en la Yellow Zone, para que un cambio de zonas no se confunda con tráfico.
SELECT v.hora,
       v.anio::VARCHAR AS anio,
       round(median(v.velocidad_mph), 2) AS velocidad_mediana_mph
FROM viajes_comparables v
JOIN zonas zo ON v.origen_id = zo.zona_id
JOIN zonas zd ON v.destino_id = zd.zona_id
WHERE v.tipo = 'yellow'
  AND v.dia_semana <= 5
  AND v.velocidad_mph IS NOT NULL
  AND zo.service_zone = 'Yellow Zone'
  AND zd.service_zone = 'Yellow Zone'
GROUP BY v.hora, v.anio
ORDER BY anio, v.hora;
