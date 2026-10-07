-- 5.6 Reglas de calidad del Ejercicio 4 aplicadas a cada anio
-- Requiere las vistas de sql/ejercicio4/00_vistas.sql.
SELECT tipo,
       left(mes_archivo, 4)::INT AS anio,
       count(*) AS registros,
       count(*) FILTER (WHERE NOT ok_fecha) AS fecha_fuera_del_mes,
       count(*) FILTER (WHERE NOT ok_duracion) AS duracion_invalida,
       count(*) FILTER (WHERE NOT ok_distancia) AS distancia_invalida,
       count(*) FILTER (WHERE NOT ok_monto) AS monto_negativo,
       round(100 * count(*) FILTER (WHERE NOT (ok_fecha AND ok_duracion AND ok_distancia AND ok_monto))
             / count(*), 2) AS pct_excluidos,
       round(100 * count(*) FILTER (WHERE passenger_count IS NULL) / count(*), 2) AS pct_null_pasajeros,
       round(100 * count(*) FILTER (WHERE payment_type = 0) / count(*), 2) AS pct_payment_0
FROM viajes
GROUP BY ALL
ORDER BY tipo, anio;
