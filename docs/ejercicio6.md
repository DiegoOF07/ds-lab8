# Ejercicio 6 - Parquet frente a tablas DuckDB

Este ejercicio compara dos estrategias para las mismas consultas:

- **Parquet directo:** DuckDB lee los archivos de `data/raw/` en cada consulta.
- **Tabla materializada:** las mismas filas se copian una vez a una base DuckDB
  (`data/processed/taxis.duckdb`) y las consultas leen la tabla.

| Archivo | Contenido |
|---|---|
| `sql/ejercicio6/00_fuente_parquet.sql` | vista sobre los Parquet de una escala (6.1) |
| `sql/ejercicio6/01_crear_tabla.sql` | materializacion de la tabla (6.2) |
| `sql/ejercicio6/b1` a `b6` | consultas del benchmark (6.3, 6.8) |
| `scripts/benchmark.py` | materializa, mide y compara resultados (6.4 a 6.6) |
| `docs/ejercicio6_materializacion.csv` | costo de crear cada tabla |
| `docs/ejercicio6_benchmark.csv` | tiempos de las 36 combinaciones |
| `notebooks/04_benchmark_parquet_vs_duckdb.ipynb` | tablas y graficas de los resultados (6.7) |

Los resultados son de la ejecucion del 7 de octubre de 2026, con 2024 y 2026
descargados, dentro del contenedor `lab` (8 CPU, 5.6 GB de RAM).

## Como ejecutar

```bash
# Materializa las tablas que falten y ejecuta el benchmark (unos 10 minutos)
docker compose exec lab python scripts/benchmark.py

# --recrear vuelve a crear las tablas; --repeticiones cambia las ejecuciones medidas
docker compose exec lab python scripts/benchmark.py --recrear --repeticiones 5

# Tablas y graficas a partir de los CSV
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/04_benchmark_parquet_vs_duckdb.ipynb
```

La base ocupa unos 2.8 GB y no se versiona (`data/processed/` esta en
`.gitignore`).

---

## Diseno del benchmark

Para que la comparacion sea valida, las dos estrategias tienen que hacer
exactamente el mismo trabajo logico:

1. **Mismas filas.** La tabla se crea con `CREATE TABLE ... AS SELECT * FROM`
   la misma vista Parquet contra la que se compara. No se limpia, no se cambian
   tipos y no se eliminan duplicados. Lo unico que cambia es donde y como estan
   guardados los datos.
2. **Misma consulta.** Cada consulta se escribe una sola vez con el marcador
   `{fuente}`. El script lo reemplaza por la vista Parquet o por la tabla; el
   resto del SQL es identico. B4 tambien usa `{zonas}`: el CSV de zonas en la
   estrategia Parquet y una tabla `zonas` en la materializada.
3. **Mismo resultado.** El script compara el resultado de ambas estrategias en
   las 18 parejas (6 consultas por 3 escalas). Los 18 fueron identicos, con una
   tolerancia de un centavo para sumas de punto flotante.
4. **Misma configuracion.** Cada combinacion (escala, estrategia, consulta)
   abre una conexion nueva con la misma configuracion (8 hilos, temporales
   limitados a 4 GB), asi que ninguna aprovecha la cache de la anterior.
5. **Medicion.** Se registra la primera ejecucion en la conexion nueva y luego
   5 ejecuciones mas, de las que se reporta la mediana, el minimo y el maximo.
   Los tiempos incluyen traer el resultado a pandas y se toman con
   `time.perf_counter()`.

---

## 6.1 Consulta directa sobre Parquet

```sql
-- sql/ejercicio6/00_fuente_parquet.sql ({vista}, {glob_yellow} y {glob_green} los rellena el script)
CREATE OR REPLACE VIEW {vista} AS
SELECT 'yellow' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
       tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff, *
           EXCLUDE (tpep_pickup_datetime, tpep_dropoff_datetime, filename)
FROM read_parquet('{glob_yellow}', filename = true, union_by_name = true)
UNION ALL BY NAME
SELECT 'green' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
       lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff, *
           EXCLUDE (lpep_pickup_datetime, lpep_dropoff_datetime, filename)
FROM read_parquet('{glob_green}', filename = true, union_by_name = true);
```

Es la misma union que la vista base del Ejercicio 4, pero sin columnas
derivadas, para que la tabla tenga las mismas columnas que los archivos.

## 6.2 Tabla materializada

```sql
-- sql/ejercicio6/01_crear_tabla.sql
CREATE OR REPLACE TABLE {tabla} AS
SELECT * FROM {vista};
```

El script la aplica a tres escalas (6.6). La tabla principal es `viajes`, con
los 71,870,407 registros de 2024 y 2026 y 25 columnas (las 24 de los Parquet
mas `mes_archivo`, sin `filename`).

| escala | tabla | filas | creacion (s) | Parquet (MiB) | tabla DuckDB (MiB) | tabla / Parquet |
|---|---|---:|---:|---:|---:|---:|
| 1 mes (2026-01) | `viajes_2026_01` | 3,765,161 | 4.3 | 62.1 | 102.0 | 1.64 |
| 2026 (8 meses) | `viajes_2026` | 30,040,469 | 33.6 | 495.7 | 815.5 | 1.65 |
| todos los anios | `viajes` | 71,870,407 | 81.4 | 1,171.7 | 1,934.2 | 1.65 |

- **Tiempo:** materializar procesa unas 880 mil filas por segundo, de forma
  lineal. La tabla completa tarda 81 s.
- **Espacio:** la tabla ocupa 1.65 veces lo que los Parquet. Ambos estan
  comprimidos, pero de forma distinta. Los Parquet de la TLC usan ZSTD, una
  compresion de proposito general muy compacta pero que hay que descomprimir.
  DuckDB usa compresion ligera por columna, que se decodifica casi sin costo:
  `pragma_storage_info` muestra BitPacking en `pickup` y `PULocationID`, ALP
  en `trip_distance` y `total_amount`, Dictionary en `tipo` y Constant en
  tramos de `payment_type`.
- Los datos quedan **duplicados**: los Parquet siguen siendo la fuente y la
  tabla es una copia que hay que regenerar si llegan archivos nuevos.

---

## 6.3 y 6.8 Consultas del benchmark

Se eligieron seis consultas del analisis del Ejercicio 4 que cubren los
patrones de acceso distintos que aparecen en el trabajo. Asi se ve en que tipo
de consulta conviene cada estrategia, no solo un promedio.

| Consulta | Origen | Patron que representa |
|---|---|---|
| B1 `b1_volumen_mensual` | Ej. 4, P1 | agregacion simple que lee 4 columnas |
| B2 `b2_hora_dia_semana` | Ej. 4, P2 | agrupacion por expresiones sobre un timestamp |
| B3 `b3_percentiles` | Ej. 4, P3 | agregados holisticos (cuantiles exactos), intensivos en CPU |
| B4 `b4_top_zonas` | Ej. 4, P7 | join con una dimension, agregacion y ventana |
| B5 `b5_filtro_selectivo` | nueva | filtro muy selectivo (un dia, una zona) |
| B6 `b6_consistencia_montos` | Ej. 4, P13 | escaneo ancho de 12 columnas con aritmetica por fila |

```sql
-- B1. Volumen e ingresos por tipo y mes
SELECT tipo, year(pickup) AS anio, month(pickup) AS mes,
       count(*) AS viajes, round(sum(total_amount), 2) AS ingresos
FROM {fuente}
WHERE strftime(pickup, '%Y-%m') = mes_archivo
GROUP BY ALL ORDER BY ALL;

-- B2. Viajes por dia de la semana y hora
SELECT tipo, isodow(pickup) AS dia_semana, hour(pickup) AS hora, count(*) AS viajes
FROM {fuente}
GROUP BY ALL ORDER BY ALL;

-- B3. Percentiles de distancia y monto total
SELECT tipo,
       round(median(trip_distance), 2) AS distancia_mediana,
       list_transform(quantile_cont(total_amount, [0.25, 0.5, 0.75, 0.95]), x -> round(x, 2)) AS total_cuartiles
FROM {fuente}
WHERE trip_distance > 0 AND trip_distance <= 200 AND total_amount >= 0
GROUP BY tipo ORDER BY tipo;

-- B4. Las 10 zonas de origen con mas viajes por tipo
SELECT v.tipo,
       row_number() OVER (PARTITION BY v.tipo ORDER BY count(*) DESC, z.zona) AS posicion,
       z.borough, z.zona, count(*) AS viajes
FROM {fuente} v
JOIN {zonas} z ON v.PULocationID = z.LocationID
GROUP BY v.tipo, z.borough, z.zona
QUALIFY posicion <= 10
ORDER BY v.tipo, posicion;

-- B5. Viajes desde JFK el 15 de enero de 2026 (fecha presente en las tres escalas)
SELECT tipo, hour(pickup) AS hora, count(*) AS viajes, round(avg(total_amount), 2) AS total_promedio
FROM {fuente}
WHERE pickup >= TIMESTAMP '2026-01-15' AND pickup < TIMESTAMP '2026-01-16'
  AND PULocationID = 132
GROUP BY ALL ORDER BY ALL;

-- B6. Cuadre del monto total por proveedor
SELECT tipo, VendorID, count(*) AS viajes,
       round(100 * avg((abs(total_amount - (fare_amount + extra + mta_tax + tip_amount + tolls_amount
             + improvement_surcharge + coalesce(Airport_fee, 0) + coalesce(ehail_fee, 0)
             + coalesce(congestion_surcharge, 0) + coalesce(cbd_congestion_fee, 0))) <= 0.01)::INT), 1)
           AS pct_cuadra_con_recargos,
       round(avg(extra), 2) AS extra_promedio
FROM {fuente}
GROUP BY ALL ORDER BY ALL;
```

---

## 6.4, 6.5 y 6.7 Resultados

**Mediana de 5 ejecuciones, en segundos**, y aceleracion de la tabla
(`parquet / tabla`):

| consulta | 1 mes: Parquet | 1 mes: tabla | 1 mes: acel. | 2026: Parquet | 2026: tabla | 2026: acel. | todos: Parquet | todos: tabla | todos: acel. |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| B1 volumen mensual | 0.534 | 0.157 | 3.4x | 2.204 | 1.487 | 1.5x | 4.928 | 3.026 | 1.6x |
| B2 hora y dia | 0.295 | 0.067 | 4.4x | 1.047 | 0.454 | 2.3x | 2.648 | 0.890 | 3.0x |
| B3 percentiles | 0.678 | 0.647 | 1.0x | 5.925 | 5.949 | 1.0x | 15.643 | 16.203 | 1.0x |
| B4 top zonas | 0.203 | 0.086 | 2.4x | 0.976 | 0.414 | 2.4x | 2.529 | 1.102 | 2.3x |
| B5 filtro selectivo | 0.161 | 0.007 | 22x | 0.414 | 0.008 | 53x | 1.006 | 0.008 | 120x |
| B6 consistencia montos | 0.362 | 0.190 | 1.9x | 2.332 | 1.013 | 2.3x | 4.912 | 2.382 | 2.1x |

**Primera ejecucion frente a las repetidas**, escala completa (en segundos):

| consulta | Parquet: primera | Parquet: mediana | tabla: primera | tabla: mediana |
|---|---:|---:|---:|---:|
| B1 | 4.672 | 4.928 | 4.402 | 3.026 |
| B2 | 2.438 | 2.648 | 1.651 | 0.890 |
| B3 | 16.749 | 15.643 | 16.696 | 16.203 |
| B4 | 2.664 | 2.529 | 1.736 | 1.102 |
| B5 | 1.003 | 1.006 | 0.075 | 0.008 |
| B6 | 5.534 | 4.912 | 5.953 | 2.382 |

El CSV completo, con minimos y maximos, esta en
`docs/ejercicio6_benchmark.csv`. La variacion entre ejecuciones fue pequena: en
la escala completa, el maximo supera a la mediana en menos de 30% en todas las
combinaciones.

## 6.6 Comportamiento segun la cantidad de datos

El notebook grafica la mediana contra los millones de filas, una grafica por
consulta. Calculando los segundos por cada millon de filas:

| consulta | Parquet 1 mes | Parquet 2026 | Parquet todos | tabla 1 mes | tabla 2026 | tabla todos |
|---|---:|---:|---:|---:|---:|---:|
| B1 | 0.142 | 0.073 | 0.069 | 0.042 | 0.049 | 0.042 |
| B2 | 0.078 | 0.035 | 0.037 | 0.018 | 0.015 | 0.012 |
| B3 | 0.180 | 0.197 | 0.218 | 0.172 | 0.198 | 0.225 |
| B4 | 0.054 | 0.032 | 0.035 | 0.023 | 0.014 | 0.015 |
| B6 | 0.096 | 0.078 | 0.068 | 0.050 | 0.034 | 0.033 |

- **Ambas estrategias escalan de forma aproximadamente lineal** con las filas.
  De 30 a 72 millones (2.4 veces), los tiempos crecen entre 2.0 y 2.7 veces.
- **Parquet tiene un costo fijo por consulta** que pesa mas con pocos datos: con
  un mes cuesta el doble por millon de filas que con 72 millones (B1: 0.142
  frente a 0.069). Ese costo es abrir los archivos, leer sus footers, resolver
  el esquema con `union_by_name` y descomprimir. Por eso la ventaja de la tabla
  es mayor en la escala pequena (B1: 3.4x con un mes y 1.6x con todo).
- **B5 se comporta distinto.** Con Parquet crece con la cantidad de archivos
  (0.16, 0.41 y 1.01 s), aunque el resultado es siempre el mismo dia. Con la
  tabla es constante (unos 0.008 s): no depende del volumen total, sino de los
  bloques que contienen ese dia.
- **B3 cuesta lo mismo en ambas** y es la unica consulta cuyo costo por millon
  de filas crece con la escala (0.18 a 0.22), porque ordenar para calcular
  cuantiles exactos crece algo mas que linealmente.

---

## 6.9 Analisis de las diferencias

Las explicaciones se verificaron con perfiles de ejecucion (`EXPLAIN ANALYZE`),
con `pragma_storage_info` y separando el costo de lectura del de calculo.

1. **La tabla es mas rapida al leer porque su compresion es mas barata de
   decodificar.** En B1, B2, B4 y B6 la tabla es entre 1.6 y 3 veces mas
   rapida. Las consultas son iguales; lo que cambia es el costo de convertir
   bytes en disco a valores en memoria. ZSTD (Parquet) requiere descomprimir
   cada pagina, mientras que BitPacking, ALP o Dictionary (DuckDB) se decodifican
   casi sin costo. La tabla ocupa 65% mas, pero se lee mas rapido.

2. **Los filtros selectivos son la mayor diferencia (hasta 120x) por la
   granularidad de los bloques.** Ambos formatos guardan el minimo y el maximo
   de cada columna por bloque, y DuckDB los usa para saltarse bloques que no
   pueden cumplir el filtro. La diferencia esta en el tamanio de esos bloques:
   - los 40 Parquet tienen solo 96 *row groups* en total, de unas 750 mil filas
     (los yellow traen 4 por archivo);
   - la tabla tiene 621 *row groups* de unas 120 mil filas, y al insertarse en
     orden de archivo quedan agrupados por mes.

   El perfil de B5 lo confirma. Con Parquet, DuckDB abre los 40 archivos (20 por
   tipo) y lee sus footers para devolver 4,694 filas, en 1.1 s. Con la tabla,
   los mapas de zonas descartan casi todos los bloques y la consulta tarda
   0.009 s.

3. **Cuando domina el calculo, el formato no importa.** En B3, solo leer y
   filtrar las columnas tarda 1.5 s desde Parquet y 0.76 s desde la tabla, pero
   la consulta completa tarda unos 15 s en ambas. Mas del 90% del tiempo es el
   calculo de los cuantiles exactos, que es identico en las dos estrategias.

4. **Gran parte de la ventaja de la tabla aparece al repetir consultas.** Con
   Parquet, la primera ejecucion y las siguientes tardan casi lo mismo (B6:
   5.53 y 4.91 s), porque cada consulta vuelve a leer y descomprimir. Con la
   tabla, la primera ejecucion en una conexion nueva es mucho mas lenta que las
   siguientes (B6: 5.95 frente a 2.38 s; B2: 1.65 frente a 0.89 s), porque carga
   los bloques del archivo `.duckdb` en el *buffer pool* y luego los reutiliza.
   En la primera ejecucion de B6 la tabla incluso fue algo mas lenta que
   Parquet, porque tiene que leer 65% mas bytes.

5. **El costo de materializar se recupera rapido si las consultas se repiten.**
   Crear la tabla completa costo 81 s. Ejecutar las 6 consultas una vez ahorra
   unos 8 s con la tabla (sumando las diferencias de las medianas en la escala
   completa). La materializacion se paga despues de unas 10 rondas, es decir,
   unas 60 consultas. Un tablero que se refresca varias veces al dia supera
   esa cifra en poco tiempo; un analisis puntual no.

### Limitaciones de la medicion

- Los archivos ya estaban en la cache de archivos del sistema operativo por los
  ejercicios anteriores, asi que la "primera ejecucion" es en una conexion
  nueva, no con el disco frio. Con disco frio, la tabla leeria 65% mas bytes y
  su desventaja en la primera ejecucion seria mayor.
- Es una sola maquina (8 CPU y 5.6 GB de RAM dentro de Docker sobre WSL2) y 5
  repeticiones por combinacion. Las diferencias de menos de 10%, como B3, deben
  leerse como empates.
- La tabla no se optimizo. Ordenarla por `pickup`, reducir los tipos (BIGINT a
  SMALLINT en codigos) o guardar solo los viajes validos la haria mas pequena y
  probablemente mas rapida. Se dejo igual a los Parquet para aislar el efecto
  de la estrategia de acceso.

---

## 6.10 Cuando usar cada estrategia

**Conviene consultar Parquet directamente cuando:**

- **Se explora o se hace un analisis puntual.** No hay que esperar una carga,
  ni para la primera consulta (como en el Ejercicio 3), ni para las unicas
  consultas de un analisis que no se repetira.
- **Los datos cambian o crecen con frecuencia.** Un archivo mensual nuevo entra
  en la siguiente consulta sin hacer nada (Ejercicio 5). Con una tabla, cada
  llegada obliga a recargar o a hacer un `INSERT` incremental controlado.
- **El espacio importa.** Los Parquet ocupan 1.65 veces menos y materializar
  duplica los datos. En este laboratorio, el disco se lleno una vez (Ejercicio 5).
- **Los mismos archivos se comparten con otras herramientas** (pandas, Spark,
  otros motores). Parquet es un formato abierto; el archivo `.duckdb` solo lo
  lee DuckDB, y de su misma version.
- **La consulta esta dominada por el calculo** (B3). Materializar no la acelera.

**Conviene materializar una tabla DuckDB cuando:**

- **Las mismas consultas se repiten muchas veces sobre los mismos datos.** Por
  ejemplo, un tablero (Ejercicio 7): la ventaja de 1.6 a 3 veces se multiplica
  por cada refresco y la materializacion se amortiza en unas 60 consultas.
- **Hay filtros selectivos por fecha, zona o tipo**, que es justo lo que hace un
  tablero con controles. La tabla responde en milisegundos (B5: 120x) y su
  tiempo no crece con el historico.
- **Se quiere aplicar la limpieza una sola vez.** Las reglas de calidad, la
  recodificacion de `RatecodeID`, la duracion de Helix y la eliminacion de
  duplicados pueden calcularse al crear la tabla, en lugar de en cada consulta.
- **Varias herramientas o usuarios consultan los mismos datos** en solo lectura,
  como Metabase conectandose a `taxis.duckdb`.

**En la practica conviene una combinacion.** Los Parquet de `data/raw/` siguen
siendo la fuente de verdad, inmutable y descargada por script. A partir de ellos
se materializa con un script reproducible una tabla curada (limpia y ordenada)
para el consumo repetido, que se regenera o se amplia por `mes_archivo` cuando
llegan archivos nuevos. La exploracion y los analisis puntuales siguen
haciendose sobre Parquet.
