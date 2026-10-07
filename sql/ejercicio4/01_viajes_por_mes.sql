-- P1. Evolucion mensual de la demanda y los ingresos por tipo de taxi
SELECT tipo, anio, mes,
       count(*) AS viajes,
       round(count(*) / day(last_day(make_date(anio, mes, 1))), 0) AS viajes_por_dia,
       round(sum(total_amount) / 1e6, 2) AS ingresos_musd,
       round(avg(total_amount), 2) AS total_promedio
FROM viajes_validos
GROUP BY tipo, anio, mes
ORDER BY tipo, anio, mes;
