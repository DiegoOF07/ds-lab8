-- P15. Valores atipicos por la regla de Tukey (Q3 + 1.5 * IQR) sobre los viajes validos
WITH metricas AS (
    SELECT tipo,
           trip_distance AS distancia_mi,
           duracion_min,
           total_amount AS total_usd,
           trip_distance / (duracion_min / 60) AS velocidad_mph
    FROM viajes_validos
), cuartiles AS (           -- una fila por tipo: [Q1, Q3] de cada metrica
    SELECT tipo,
           quantile_cont(distancia_mi, [0.25, 0.75]) AS q_distancia_mi,
           quantile_cont(duracion_min, [0.25, 0.75]) AS q_duracion_min,
           quantile_cont(total_usd, [0.25, 0.75]) AS q_total_usd,
           quantile_cont(velocidad_mph, [0.25, 0.75]) AS q_velocidad_mph
    FROM metricas
    GROUP BY tipo
), limites AS (             -- limite superior de Tukey por tipo y metrica
    SELECT tipo,
           q_distancia_mi[2] + 1.5 * (q_distancia_mi[2] - q_distancia_mi[1]) AS lim_distancia_mi,
           q_duracion_min[2] + 1.5 * (q_duracion_min[2] - q_duracion_min[1]) AS lim_duracion_min,
           q_total_usd[2] + 1.5 * (q_total_usd[2] - q_total_usd[1]) AS lim_total_usd,
           q_velocidad_mph[2] + 1.5 * (q_velocidad_mph[2] - q_velocidad_mph[1]) AS lim_velocidad_mph
    FROM cuartiles
), conteos AS (
    SELECT m.tipo, count(*) AS viajes,
           count(*) FILTER (WHERE distancia_mi > lim_distancia_mi) AS atip_distancia_mi,
           count(*) FILTER (WHERE duracion_min > lim_duracion_min) AS atip_duracion_min,
           count(*) FILTER (WHERE total_usd > lim_total_usd) AS atip_total_usd,
           count(*) FILTER (WHERE velocidad_mph > lim_velocidad_mph) AS atip_velocidad_mph,
           max(distancia_mi) AS max_distancia_mi,
           max(duracion_min) AS max_duracion_min,
           max(total_usd) AS max_total_usd,
           max(velocidad_mph) AS max_velocidad_mph,
           count(*) FILTER (WHERE velocidad_mph > 80) AS mas_de_80_mph
    FROM metricas m
    JOIN limites l USING (tipo)
    GROUP BY m.tipo
), largo AS (               -- una fila por tipo y metrica
    SELECT c.tipo, u.metrica, u.q, u.limite, u.atipicos, u.maximo, c.viajes, c.mas_de_80_mph
    FROM conteos c
    JOIN cuartiles q USING (tipo)
    JOIN limites l USING (tipo),
    LATERAL (VALUES
        ('distancia_mi', q.q_distancia_mi, l.lim_distancia_mi, c.atip_distancia_mi, c.max_distancia_mi),
        ('duracion_min', q.q_duracion_min, l.lim_duracion_min, c.atip_duracion_min, c.max_duracion_min),
        ('total_usd', q.q_total_usd, l.lim_total_usd, c.atip_total_usd, c.max_total_usd),
        ('velocidad_mph', q.q_velocidad_mph, l.lim_velocidad_mph, c.atip_velocidad_mph, c.max_velocidad_mph)
    ) AS u(metrica, q, limite, atipicos, maximo)
)
SELECT tipo, metrica,
       round(q[1], 2) AS q1,
       round(q[2], 2) AS q3,
       round(limite, 2) AS limite_superior,
       atipicos,
       round(100 * atipicos / viajes, 2) AS pct_atipicos,
       round(maximo, 2) AS maximo,
       CASE WHEN metrica = 'velocidad_mph' THEN mas_de_80_mph END AS mas_de_80_mph
FROM largo
ORDER BY metrica, tipo;
