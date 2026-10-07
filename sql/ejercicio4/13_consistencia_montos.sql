-- P13. Cuadra total_amount con la suma de sus componentes?
-- Se prueban dos formulas: con y sin congestion_surcharge y cbd_congestion_fee.
WITH d AS (
    SELECT tipo, VendorID, coalesce(payment_type = 0, false) AS es_flex, extra,
           fare_amount + extra + mta_tax + tip_amount + tolls_amount + improvement_surcharge
               + coalesce(Airport_fee, 0) + coalesce(ehail_fee, 0) AS base,
           coalesce(congestion_surcharge, 0) + coalesce(cbd_congestion_fee, 0) AS recargos_congestion,
           total_amount
    FROM viajes_validos
)
SELECT tipo, VendorID, es_flex,
       count(*) AS viajes,
       round(100 * avg((abs(total_amount - base - recargos_congestion) <= 0.01)::INT), 1) AS pct_cuadra_con_recargos,
       round(100 * avg((abs(total_amount - base) <= 0.01)::INT), 1) AS pct_cuadra_sin_recargos,
       round(avg(extra), 2) AS extra_promedio,
       round(avg(recargos_congestion), 2) AS recargos_promedio
FROM d
GROUP BY ALL
HAVING count(*) >= 100
ORDER BY tipo, VendorID, es_flex;
