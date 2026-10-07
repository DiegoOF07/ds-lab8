-- P2. Distribucion de los viajes por dia de la semana y hora de inicio
SELECT tipo, dia_semana, hora,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 3) AS pct_del_tipo
FROM viajes_validos
GROUP BY tipo, dia_semana, hora
ORDER BY tipo, dia_semana, hora;
