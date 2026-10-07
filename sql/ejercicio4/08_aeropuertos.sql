-- P8. Peso y caracteristicas de los viajes que tocan un aeropuerto
-- Zonas: 132 = JFK, 138 = LaGuardia, 1 = Newark (EWR)
SELECT tipo,
       CASE WHEN 132 IN (PULocationID, DOLocationID) THEN 'JFK'
            WHEN 138 IN (PULocationID, DOLocationID) THEN 'LaGuardia'
            WHEN 1 IN (PULocationID, DOLocationID) THEN 'Newark'
            ELSE 'Sin aeropuerto' END AS aeropuerto,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_viajes,
       round(100 * sum(total_amount) / sum(sum(total_amount)) OVER (PARTITION BY tipo), 2) AS pct_ingresos,
       round(median(trip_distance), 2) AS distancia_mediana_mi,
       round(median(duracion_min), 1) AS duracion_mediana_min,
       round(median(total_amount), 2) AS total_mediano
FROM viajes_validos
GROUP BY tipo, aeropuerto
ORDER BY tipo, viajes DESC;
