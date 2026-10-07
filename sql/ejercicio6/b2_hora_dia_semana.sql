-- B2. Viajes por dia de la semana y hora (Ej. 4, P2)
-- Patron: agrupacion por expresiones calculadas sobre un timestamp.
SELECT tipo, isodow(pickup) AS dia_semana, hour(pickup) AS hora,
       count(*) AS viajes
FROM {fuente}
GROUP BY ALL
ORDER BY ALL;
