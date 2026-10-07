-- 5.7 Version escalable de sql/ejercicio3/15_duplicados.sql
-- La original compara filas completas con SELECT DISTINCT *, lo que con 2024 y 2026
-- juntos supera la memoria y el limite de temporales. Aqui se compara un hash de
-- 64 bits de cada fila: la tabla de distintos guarda un entero por fila en lugar de
-- 20 columnas. La probabilidad de colision con ~70 millones de filas es del orden
-- de 1e-4, despreciable para contar duplicados.
SELECT regexp_extract(filename, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(filename, '/(\d{4})/', 1)::INT AS anio,
       count(*) AS registros,
       count(*) - count(DISTINCT hash(*COLUMNS(* EXCLUDE (filename)))) AS filas_duplicadas
FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
GROUP BY ALL
ORDER BY anio, tipo;
