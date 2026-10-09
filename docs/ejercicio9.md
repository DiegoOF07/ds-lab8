# Ejercicio 9 - Discusión

## 9.1 Características de DuckDB más útiles

La más útil fue leer Parquet con globs y `union_by_name`. Una misma consulta
leyó 16, 40 y 64 archivos sin cambios, y rellenó con `NULL` las columnas que no
existían en 2024, como `cbd_congestion_fee` (Ej. 5 y 8). Las funciones de
metadata (`parquet_file_metadata`, `parquet_schema`) permitieron validar conteos
y esquemas de los tres años al instante, sin leer los datos.

También resultaron clave el SQL analítico (`FILTER`, `QUALIFY`, `UNPIVOT`,
cuantiles exactos) y las vistas. Las vistas concentraron las reglas de calidad,
y las 17 consultas del Ejercicio 4 funcionaron igual con dos y con tres años.
Que el motor sea embebido permitió que Python, los notebooks y Metabase usaran
el mismo archivo sin un servidor. Por último, la escritura a disco con un límite
configurable (`max_temp_directory_size`) evitó que se repitiera el incidente del
Ejercicio 5, en el que una consulta llenó el disco de Docker.

## 9.2 Consultar Parquet directamente

La ventaja principal es que no hay carga previa: un archivo nuevo entra en la
siguiente consulta, como ocurrió con 2024 y 2025. Además, los Parquet ocupan
1.65 veces menos que una tabla DuckDB, se pueden leer desde otras herramientas
y DuckDB lee solo las columnas que necesita. Un conteo y un promedio sobre 121
millones de filas tardaron 0.1 s.

La limitación es el costo por consulta. Cada lectura abre los archivos y
descomprime ZSTD, por lo que fue de 1.6 a 3 veces más lenta que la tabla
(Ej. 6). Con filtros selectivos la diferencia llegó a 120 veces, porque los
archivos tienen pocos *row groups* de unas 750 mil filas y DuckDB no puede
saltarse bloques más finos. Además, la limpieza se recalcula en cada consulta, y
una ruta fija en el SQL puede ignorar datos sin avisar, como pasa con las
consultas del Ejercicio 3, que solo leen `/2026/`.

## 9.3 Tablas materializadas en DuckDB

Materializar hizo las lecturas de 1.6 a 3 veces más rápidas, y hasta 120 veces
más rápidas en filtros selectivos, con un tiempo que no crece con el histórico
(Ej. 6). También permitió aplicar la limpieza una sola vez: el tablero responde
cada indicador en menos de 5 s sobre 117 millones de filas curadas.

El precio es mantener una copia de los datos. La base del tablero ocupa 2.4 GB y
hay que reconstruirla cuando llega información nueva, como en el Ejercicio 8,
que además obligó a reiniciar Metabase. El archivo admite un solo proceso con
escritura y depende de la versión de DuckDB, que debe coincidir con la del
driver de Metabase. Materializar 72 millones de filas tomó 81 s, y no acelera las
consultas dominadas por el cálculo, como los cuantiles.

## 9.4 Frente a cargar todo con Pandas

Cargar todo en pandas no habría sido viable. Un mes de yellow ocupa 0.64 GiB en
un DataFrame, así que los tres años necesitarían unos 16.8 GiB: el triple de la
RAM del contenedor (5.6 GB) y ocho veces lo que pesan los Parquet en disco. Con
DuckDB, la misma información se agrega en 0.1 s porque solo se leen las columnas
y filas necesarias, por bloques, y se usa disco si falta memoria. La medición se
reproduce con `python scripts/memoria_pandas.py`.

pandas sigue siendo útil al final del flujo: los resultados de DuckDB tienen
decenas de filas y los notebooks los convierten en DataFrames para mostrarlos.
Además, como las consultas viven en archivos SQL, las reutilizan por igual los
notebooks, los scripts y Metabase.

## 9.5 Incorporar datos con cambios mínimos

Incorporar 2025 requirió cambiar una línea: agregar el año a la constante
`ANIOS`. Eso fue posible porque cada archivo vive en `data/raw/<tipo>/<año>/`
con su nombre original, la descarga solo baja lo que falta y deja un manifiesto
por año, y las consultas leen globs y vistas en lugar de listas de archivos.

El análisis tampoco dependía de años fijos. Los meses comparables y el año se
calculan desde los datos, los scripts del tablero se pueden volver a ejecutar y
los colores de 2025 estaban asignados desde el Ejercicio 7. Por eso el tablero
se actualizó reconstruyendo la base, sin tocar las consultas.

## 9.6 Qué automatizar en producción

Lo primero sería la descarga mensual programada. La TLC publica con unos dos
meses de atraso, y el script ya distingue un mes no publicado de una descarga
fallida. Después, los controles de calidad con alertas: la anomalía de Flex Fare
de 2025 se encontró a mano, cuando el porcentaje excluido de yellow se duplicó,
y una alerta por mes y proveedor la habría detectado sola.

También conviene automatizar:

- la materialización incremental por mes, en lugar de reconstruir toda la base;
- la actualización de Metabase sin reiniciarlo;
- la prueba de regresión de las consultas, como la del notebook del Ejercicio 8,
  y la detección de cambios de esquema en cada carga.

## 9.7 Decisiones de diseño para la reproducibilidad

La base fue un ambiente en Docker con versiones fijas, incluida la coincidencia
entre DuckDB y el driver de Metabase. Los datos se mantuvieron fuera de Git: se
obtienen con un script y se verifican por tamaño, footer Parquet y manifiesto.
Todo lo que está en `data/processed/` se regenera con un comando.

Las consultas viven en archivos SQL que ejecutan los notebooks y los scripts, y
cada una está documentada con su resultado y la decisión que motivó. El tablero
se crea por API desde el repositorio en lugar de armarse a mano. El benchmark,
por su parte, usa conexiones nuevas y repeticiones, y verifica que ambas
estrategias devuelvan el mismo resultado.

## 9.8 Lo que no habría sido evidente con datos pequeños

Con datos pequeños no habríamos chocado con los límites físicos: en el
Ejercicio 5 un `DISTINCT *` agotó la memoria y una consulta escribió más de 8 GB de
temporales. Tampoco habríamos visto que errores raros se vuelven miles de
registros (6,586 viajes de más de 80 mph en el Ejercicio 7) y dominan los
máximos, lo que llevó a usar medianas.

Lo más importante fue que la calidad cambia con el tiempo y con el proveedor.
Helix no registra la hora de bajada, `extra` significa cosas distintas según el
proveedor, y los montos de Flex Fare se capturaron mal durante 11 meses de 2025.
Nada de eso aparece en una muestra; solo se ve al agrupar por mes y proveedor.

Por último, más datos pueden cambiar una conclusión. Con 2024 y 2026, yellow
parecía crecer sin pausa, pero 2025 mostró un pico y una caída. Y comparar
periodos exige usar los mismos meses: con años incompletos, el crecimiento daba
+8.5% en lugar de +12.6%. El rendimiento también depende de cómo están guardados
los datos, no solo de la consulta: la misma consulta varió hasta 120 veces según
el formato.
