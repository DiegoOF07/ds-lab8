-- I3. Perfil horario de la demanda
-- Pregunta: ¿a qué horas se usa cada servicio?
-- Porcentaje dentro de cada tipo y franja: compara la forma del perfil, no el volumen.
SELECT hora,
       tipo || CASE WHEN dia_semana <= 5 THEN ' laboral' ELSE ' fin de semana' END AS serie,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo, dia_semana <= 5), 2) AS pct_viajes
FROM viajes
GROUP BY hora, tipo, dia_semana <= 5
ORDER BY serie, hora;
