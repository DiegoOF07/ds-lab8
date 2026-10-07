-- P10. Peso mensual de los viajes Flex Fare en yellow, por proveedor (VendorID)
SELECT anio, mes,
       count(*) AS viajes,
       round(100 * avg((payment_type = 0)::INT), 2) AS pct_flex,
       round(100 * avg((payment_type = 0)::INT) FILTER (WHERE VendorID = 1), 2) AS pct_flex_vendor1,
       round(100 * avg((payment_type = 0)::INT) FILTER (WHERE VendorID = 2), 2) AS pct_flex_vendor2,
       count(*) FILTER (WHERE VendorID = 6) AS viajes_vendor6,
       round(100 * avg((payment_type = 0)::INT) FILTER (WHERE VendorID = 6), 2) AS pct_flex_vendor6,
       count(*) FILTER (WHERE VendorID = 7) AS viajes_vendor7,
       round(100 * avg((payment_type = 0)::INT) FILTER (WHERE VendorID = 7), 2) AS pct_flex_vendor7
FROM viajes_validos
WHERE tipo = 'yellow'
GROUP BY ALL
ORDER BY anio, mes;
