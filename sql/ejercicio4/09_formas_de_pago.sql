-- P9. Formas de pago: participacion en viajes e ingresos, y propinas registradas
SELECT tipo, forma_pago,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_viajes,
       round(100 * sum(total_amount) / sum(sum(total_amount)) OVER (PARTITION BY tipo), 2) AS pct_ingresos,
       round(median(total_amount), 2) AS total_mediano,
       round(100 * avg((tip_amount > 0)::INT), 1) AS pct_con_propina
FROM viajes_validos
GROUP BY tipo, forma_pago
ORDER BY tipo, viajes DESC;
