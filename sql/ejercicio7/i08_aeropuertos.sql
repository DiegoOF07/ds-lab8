-- I8. Peso de los viajes de aeropuerto
-- Pregunta: ¿cuánto aportan los aeropuertos en viajes y en ingresos?
-- Aeropuerto: origen o destino en JFK (132), LaGuardia (138) o Newark (1).
SELECT tipo || ' ' || anio AS grupo,
       round(100 * avg((origen_id IN (1, 132, 138) OR destino_id IN (1, 132, 138))::INT), 2) AS pct_viajes,
       round(100 * sum(total) FILTER (WHERE origen_id IN (1, 132, 138) OR destino_id IN (1, 132, 138))
             / sum(total), 2) AS pct_ingresos
FROM viajes_comparables
GROUP BY tipo, anio
ORDER BY tipo DESC, anio;
