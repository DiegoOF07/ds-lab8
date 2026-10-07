-- B1. Volumen e ingresos por tipo y mes (Ej. 4, P1)
-- Patron: agregacion simple que lee pocas columnas.
SELECT tipo, year(pickup) AS anio, month(pickup) AS mes,
       count(*) AS viajes,
       round(sum(total_amount), 2) AS ingresos
FROM {fuente}
WHERE strftime(pickup, '%Y-%m') = mes_archivo
GROUP BY ALL
ORDER BY ALL;
