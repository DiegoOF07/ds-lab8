-- I12. Velocidad mediana por mes en el centro de Manhattan (yellow, días laborales de 5 a 21 h)
-- Pregunta: ¿cambió la congestión cuando empezó el cargo por congestión (enero de 2025)?
-- Mismo filtro de zona que I4, en el horario en que se cobra el cargo.
SELECT make_date(v.anio, v.mes, 1) AS mes,
       round(median(v.velocidad_mph), 2) AS velocidad_mediana_mph
FROM viajes v
JOIN zonas zo ON v.origen_id = zo.zona_id
JOIN zonas zd ON v.destino_id = zd.zona_id
WHERE v.tipo = 'yellow'
  AND v.dia_semana <= 5
  AND v.hora BETWEEN 5 AND 20
  AND v.velocidad_mph IS NOT NULL
  AND zo.service_zone = 'Yellow Zone'
  AND zd.service_zone = 'Yellow Zone'
GROUP BY ALL
ORDER BY mes;
