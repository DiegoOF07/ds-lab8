-- I2a. Viajes por día en cada mes, taxis amarillos
-- Pregunta: ¿cómo evoluciona la demanda durante el año y entre años?
SELECT mes,
       anio::VARCHAR AS anio,       -- texto, para que Metabase lo use como serie
       round(count(*) / day(last_day(make_date(anio, mes, 1))), 0) AS viajes_por_dia
FROM viajes
WHERE tipo = 'yellow'
GROUP BY anio, mes
ORDER BY anio, mes;
