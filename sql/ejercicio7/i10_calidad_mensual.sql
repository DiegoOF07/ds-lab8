-- I10. Registros excluidos por las reglas de calidad
-- Pregunta: ¿qué tan confiables son los datos de cada mes y tipo?
SELECT make_date(anio, mes, 1) AS mes,
       tipo,
       round(100 * sum(excluidos) / sum(registros), 2) AS pct_excluidos
FROM calidad_mensual
GROUP BY ALL
ORDER BY tipo DESC, mes;
