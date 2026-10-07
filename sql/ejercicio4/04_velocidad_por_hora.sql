-- P4. Velocidad, duracion y distancia medianas por hora en dias laborales
SELECT tipo, hora,
       count(*) AS viajes,
       round(median(trip_distance / (duracion_min / 60)), 1) AS velocidad_mediana_mph,
       round(median(duracion_min), 1) AS duracion_mediana_min,
       round(median(trip_distance), 2) AS distancia_mediana_mi
FROM viajes_validos
WHERE dia_semana <= 5          -- lunes a viernes
  AND duracion_min >= 1        -- evita velocidades infladas por duraciones de segundos
GROUP BY ALL
ORDER BY tipo, hora;
