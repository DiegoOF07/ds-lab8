-- B6. Cuadre del monto total por proveedor (Ej. 4, P13)
-- Patron: escaneo ancho (12 columnas) con expresiones aritmeticas por fila.
SELECT tipo, VendorID,
       count(*) AS viajes,
       round(100 * avg((abs(total_amount - (fare_amount + extra + mta_tax + tip_amount + tolls_amount
             + improvement_surcharge + coalesce(Airport_fee, 0) + coalesce(ehail_fee, 0)
             + coalesce(congestion_surcharge, 0) + coalesce(cbd_congestion_fee, 0))) <= 0.01)::INT), 1)
           AS pct_cuadra_con_recargos,
       round(avg(extra), 2) AS extra_promedio
FROM {fuente}
GROUP BY ALL
ORDER BY ALL;
