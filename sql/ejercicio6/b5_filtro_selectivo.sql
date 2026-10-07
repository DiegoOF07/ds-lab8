-- B5. Viajes desde JFK en un solo dia (15 de enero de 2026, presente en las tres escalas)
-- Patron: filtro muy selectivo sobre el timestamp, donde importa poder saltar bloques.
SELECT tipo, hour(pickup) AS hora,
       count(*) AS viajes,
       round(avg(total_amount), 2) AS total_promedio
FROM {fuente}
WHERE pickup >= TIMESTAMP '2026-01-15' AND pickup < TIMESTAMP '2026-01-16'
  AND PULocationID = 132
GROUP BY ALL
ORDER BY ALL;
