-- P12. Distribucion de la propina (como % de la tarifa) en viajes pagados con tarjeta
WITH t AS (
    SELECT tipo, 100 * tip_amount / fare_amount AS pct_propina
    FROM viajes_validos
    WHERE payment_type = 1 AND fare_amount > 0
)
SELECT tipo,
       CASE WHEN pct_propina = 0 THEN '1. 0%'
            WHEN pct_propina < 10 THEN '2. (0, 10)'
            WHEN pct_propina < 15 THEN '3. [10, 15)'
            WHEN pct_propina < 20 THEN '4. [15, 20)'
            WHEN pct_propina < 25 THEN '5. [20, 25)'
            WHEN pct_propina < 30 THEN '6. [25, 30)'
            ELSE '7. 30% o mas' END AS rango_propina,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_del_tipo
FROM t
GROUP BY tipo, rango_propina
ORDER BY tipo, rango_propina;
