-- B3. Percentiles de distancia y monto total (Ej. 4, P3)
-- Patron: agregados holisticos (cuantiles exactos), que necesitan todos los valores.
SELECT tipo,
       round(median(trip_distance), 2) AS distancia_mediana,
       list_transform(quantile_cont(total_amount, [0.25, 0.5, 0.75, 0.95]), x -> round(x, 2)) AS total_cuartiles
FROM {fuente}
WHERE trip_distance > 0 AND trip_distance <= 200 AND total_amount >= 0
GROUP BY tipo
ORDER BY tipo;
