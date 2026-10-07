-- 5.6 Comparacion de 2024 y 2026 en los meses que ambos anios tienen (enero a agosto)
-- Requiere las vistas de sql/ejercicio4/00_vistas.sql.
WITH meses_comunes AS (
    SELECT mes
    FROM viajes_validos
    GROUP BY mes
    HAVING count(DISTINCT anio) = (SELECT count(DISTINCT anio) FROM viajes_validos)
)
SELECT tipo, anio,
       count(DISTINCT mes) AS meses,
       round(count(*) / count(DISTINCT pickup::DATE), 0) AS viajes_por_dia,
       round(avg(total_amount), 2) AS total_promedio,
       round(median(trip_distance), 2) AS distancia_mediana_mi,
       round(median(duracion_min), 1) AS duracion_mediana_min,
       -- coalesce: un payment_type NULL cuenta en el denominador como "otro"
       round(100 * avg(coalesce(payment_type = 1, false)::INT), 2) AS pct_tarjeta,
       round(100 * avg(coalesce(payment_type = 2, false)::INT), 2) AS pct_efectivo,
       round(100 * avg(coalesce(payment_type = 0, false)::INT), 2) AS pct_flex,
       round(100 * avg((payment_type IS NULL)::INT), 2) AS pct_sin_dato
FROM viajes_validos
WHERE mes IN (SELECT mes FROM meses_comunes)
GROUP BY tipo, anio
ORDER BY tipo, anio;
