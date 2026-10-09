-- I1. Resumen por tipo y año
-- Pregunta: ¿qué tamaño tiene cada servicio y cómo cambia entre años?
SELECT tipo,
       anio::VARCHAR AS anio,
       min(mes) || ' a ' || max(mes) AS meses,
       round(count(*) / count(DISTINCT pickup::DATE), 0) AS viajes_por_dia,
       round(sum(total) / count(DISTINCT pickup::DATE) / 1e3, 1) AS ingresos_por_dia_miles_usd,
       round(median(total), 2) AS total_mediano_usd,
       round(median(distancia_mi), 2) AS distancia_mediana_mi,
       round(median(duracion_min), 1) AS duracion_mediana_min
FROM viajes_comparables
GROUP BY tipo, anio
ORDER BY tipo DESC, anio;
