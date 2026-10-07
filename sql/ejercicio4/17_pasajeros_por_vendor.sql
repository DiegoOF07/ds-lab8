-- P17. Los viajes de 3 a 6 pasajeros en green se comportan como viajes de grupo?
SELECT VendorID, passenger_count,
       count(*) AS viajes,
       round(median(trip_distance), 2) AS distancia_mediana_mi,
       round(median(total_amount), 2) AS total_mediano
FROM viajes_validos
WHERE tipo = 'green' AND passenger_count BETWEEN 3 AND 6
GROUP BY VendorID, passenger_count
ORDER BY VendorID, passenger_count;
