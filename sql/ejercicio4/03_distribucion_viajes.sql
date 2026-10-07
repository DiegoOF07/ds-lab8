-- P3. Distribucion de distancia, duracion, monto total y velocidad por tipo
WITH metricas AS (
    SELECT tipo,
           trip_distance AS distancia_mi,
           duracion_min,
           total_amount AS total_usd,
           trip_distance / (duracion_min / 60) AS velocidad_mph
    FROM viajes_validos
), largo AS (
    UNPIVOT metricas
    ON distancia_mi, duracion_min, total_usd, velocidad_mph
    INTO NAME metrica VALUE valor
), resumen AS (
    SELECT tipo, metrica,
           avg(valor) AS promedio,
           quantile_cont(valor, [0.05, 0.25, 0.5, 0.75, 0.95, 0.99]) AS q,
           max(valor) AS maximo
    FROM largo
    GROUP BY ALL
)
SELECT tipo, metrica,
       round(promedio, 2) AS promedio,
       round(q[1], 2) AS p05, round(q[2], 2) AS p25, round(q[3], 2) AS mediana,
       round(q[4], 2) AS p75, round(q[5], 2) AS p95, round(q[6], 2) AS p99,
       round(maximo, 2) AS maximo
FROM resumen
ORDER BY metrica, tipo;
