-- I11. Viajes por aplicación por mes
-- Pregunta: ¿cómo creció la contratación por aplicación entre 2024 y 2026?
SELECT make_date(anio, mes, 1) AS mes,
       tipo,
       round(100 * avg((forma_pago IN ('Flex Fare', 'Sin dato'))::INT), 2) AS pct_aplicacion
FROM viajes
GROUP BY ALL
ORDER BY tipo DESC, mes;
