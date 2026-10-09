-- I7. Propina sobre la tarifa, pagos con tarjeta
-- Pregunta: ¿cuánta propina se deja y cómo cambia?
-- Solo tarjeta: las propinas en efectivo no se registran (Ej. 4, P9).
WITH t AS (
    SELECT tipo, anio, 100 * propina / tarifa AS pct
    FROM viajes_comparables
    WHERE payment_type = 1 AND tarifa > 0
)
SELECT tipo || ' ' || anio AS grupo,
       CASE WHEN pct = 0 THEN '1. sin propina'
            WHEN pct < 20 THEN '2. menos de 20%'
            WHEN pct < 25 THEN '3. 20% a 25%'
            WHEN pct < 30 THEN '4. 25% a 30%'
            ELSE '5. 30% o más' END AS tramo,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo, anio), 2) AS pct_viajes
FROM t
GROUP BY tipo, anio, tramo
ORDER BY tipo DESC, anio, tramo;
