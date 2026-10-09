-- I6. Formas de pago
-- Pregunta: ¿cómo pagan los pasajeros y cómo cambia con el tiempo?
-- 'Aplicación' junta Flex Fare (yellow) y los viajes sin forma de pago de green (Ej. 4, P11).
SELECT tipo || ' ' || anio AS grupo,
       CASE WHEN forma_pago IN ('Flex Fare', 'Sin dato') THEN 'Aplicación'
            WHEN forma_pago IN ('Tarjeta', 'Efectivo') THEN forma_pago
            ELSE 'Otros' END AS forma,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo, anio), 2) AS pct_viajes
FROM viajes_comparables
GROUP BY tipo, anio, forma
ORDER BY tipo DESC, anio,
         list_position(['Tarjeta', 'Efectivo', 'Aplicación', 'Otros'], forma);
