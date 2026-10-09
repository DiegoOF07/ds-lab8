-- I5. Total mediano por viaje según el canal
-- Pregunta: ¿cuánto cuesta un viaje y cuánto más cuesta pedirlo por aplicación?
-- Se usa el total porque los componentes de los viajes por aplicación están incompletos (Ej. 4, P13).
SELECT tipo || ' ' || anio AS grupo,
       CASE WHEN forma_pago IN ('Flex Fare', 'Sin dato') THEN 'Aplicación' ELSE 'Taxímetro' END AS canal,
       round(median(total), 2) AS total_mediano_usd
FROM viajes_comparables
WHERE forma_pago IN ('Tarjeta', 'Efectivo', 'Flex Fare', 'Sin dato')
GROUP BY tipo, anio, canal
ORDER BY tipo DESC, anio, canal DESC;
