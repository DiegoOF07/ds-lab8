-- P5. Cantidad de pasajeros por viaje
SELECT tipo,
       CASE WHEN passenger_count IS NULL THEN 'sin dato'
            WHEN passenger_count >= 7 THEN '7+'
            ELSE passenger_count::VARCHAR END AS pasajeros,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_del_tipo
FROM viajes_validos
GROUP BY tipo, pasajeros
ORDER BY tipo, pasajeros;
