-- P14. Cuantos registros incumplen cada regla de calidad y cuantos se excluyen en total
-- Un registro puede incumplir varias reglas, por eso las columnas no suman el total.
SELECT tipo,
       count(*) AS registros,
       count(*) FILTER (WHERE NOT ok_fecha) AS fecha_fuera_del_mes,
       count(*) FILTER (WHERE NOT ok_duracion) AS duracion_invalida,
       count(*) FILTER (WHERE NOT ok_distancia) AS distancia_invalida,
       count(*) FILTER (WHERE NOT ok_monto) AS monto_negativo,
       count(*) FILTER (WHERE NOT (ok_fecha AND ok_duracion AND ok_distancia AND ok_monto)) AS excluidos,
       round(100 * count(*) FILTER (WHERE NOT (ok_fecha AND ok_duracion AND ok_distancia AND ok_monto))
             / count(*), 2) AS pct_excluidos
FROM viajes
GROUP BY tipo
ORDER BY tipo;
