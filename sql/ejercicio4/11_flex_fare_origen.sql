-- P11. Origen de la solicitud (request_source) segun la forma de pago
-- request_source solo existe desde junio de 2026 (Ej. 3, consulta 07)
SELECT tipo, forma_pago,
       coalesce(request_source, 'NULL') AS request_source,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo, forma_pago), 2) AS pct_de_la_forma_pago
FROM viajes_validos
WHERE make_date(anio, mes, 1) >= DATE '2026-06-01'
GROUP BY tipo, forma_pago, request_source
HAVING count(*) >= 100
ORDER BY tipo, forma_pago, viajes DESC;
