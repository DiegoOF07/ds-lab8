# Ejercicio 3 - Consultas directas sobre archivos Parquet

Todas las consultas se ejecutan con DuckDB 1.5.5 directamente sobre los archivos
Parquet descargados por `scripts/download_data.py`, sin crear tablas ni importar
datos. Cada consulta esta en `sql/ejercicio3/` y el notebook
`notebooks/01_exploracion_parquet.ipynb` las ejecuta en orden y muestra los
resultados.

Las rutas son relativas a la raiz del proyecto (`/workspace` dentro del
contenedor). Los resultados corresponden a los datos publicados por la TLC al
5 de octubre de 2026: enero a agosto de 2026 para cada tipo de taxi.

## Como ejecutar

```bash
# Ejecutar el notebook completo y guardar las salidas
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/01_exploracion_parquet.ipynb

# O una sola consulta
docker compose exec lab python -c \
    "import duckdb; print(duckdb.sql(open('sql/ejercicio3/01_conteo_archivos.sql').read()))"
```

## Vista comun para las consultas de calidad

Yellow y green nombran distinto las fechas (`tpep_*` y `lpep_*`) y cada tipo
tiene columnas propias. Las consultas 10 a 14, 16 y 17 empiezan con el mismo
CTE, `viajes`. Ese CTE renombra las fechas a `pickup`/`dropoff`, agrega `tipo` y
`mes_archivo` (este ultimo sale del nombre del archivo) y une ambos tipos con
`UNION ALL BY NAME`, que llena con `NULL` las columnas que no existen en uno de
los lados. Es una vista en memoria: no materializa nada.

```sql
WITH viajes AS (
    SELECT 'yellow' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff, *
               EXCLUDE (tpep_pickup_datetime, tpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/yellow/2026/*.parquet', filename = true, union_by_name = true)
    UNION ALL BY NAME
    SELECT 'green' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff, *
               EXCLUDE (lpep_pickup_datetime, lpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/green/2026/*.parquet', filename = true, union_by_name = true)
)
```

`union_by_name = true` es necesario porque `request_source` no existe en todos
los archivos (ver consulta 07).

---

## 3.1 Cantidad de archivos

### 01 - `01_conteo_archivos.sql`

```sql
SELECT regexp_extract(file, 'raw/(\w+)/', 1) AS tipo,
       count(*) AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS ultimo_mes
FROM glob('data/raw/*/2026/*.parquet')
GROUP BY ALL
ORDER BY tipo;
```

- **Objetivo:** contar los archivos disponibles por tipo y el rango de meses que cubren.
- **Fuente:** listado de `data/raw/*/2026/*.parquet`. `glob()` solo lista nombres y no abre los archivos.
- **Resultado:**

| tipo   | archivos | primer_mes | ultimo_mes |
|--------|---------:|------------|------------|
| green  | 8        | 2026-01    | 2026-08    |
| yellow | 8        | 2026-01    | 2026-08    |

- **Decision:** hay 16 archivos, lo mismo que reporta el manifiesto de la
  descarga. Septiembre a diciembre todavia no estan publicados, asi que todo
  analisis "anual" de 2026 cubre en realidad solo enero a agosto.

## 3.2 Cantidad de registros

### 02 - `02_registros_metadata.sql`

```sql
SELECT regexp_extract(file_name, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(file_name, '(\d{4}-\d{2})\.parquet', 1) AS mes,
       num_rows AS registros,
       num_row_groups AS row_groups
FROM parquet_file_metadata('data/raw/*/2026/*.parquet')
ORDER BY tipo, mes;
```

- **Objetivo:** obtener los registros por archivo leyendo solo el footer de cada Parquet, sin escanear los datos.
- **Fuente:** los 16 archivos de `data/raw/*/2026/`.
- **Resultado:**

| mes     | yellow    | green  |
|---------|----------:|-------:|
| 2026-01 | 3,724,889 | 40,272 |
| 2026-02 | 3,399,866 | 37,373 |
| 2026-03 | 3,952,451 | 44,208 |
| 2026-04 | 3,831,240 | 44,238 |
| 2026-05 | 4,090,836 | 44,921 |
| 2026-06 | 3,837,248 | 44,163 |
| 2026-07 | 3,530,109 | 41,252 |
| 2026-08 | 3,336,716 | 40,687 |

  Cada archivo yellow tiene 4 row groups y cada green tiene 1.

- **Decision:** los volumenes mensuales son estables, sin meses vacios ni
  anormalmente pequenos, lo que confirma que ningun archivo quedo truncado.
  Green representa apenas un 1.1% de los viajes.

### 03 - `03_registros_conteo.sql`

```sql
SELECT regexp_extract(filename, 'raw/(\w+)/', 1) AS tipo,
       count(*) AS registros
FROM read_parquet('data/raw/*/2026/*.parquet', filename = true, union_by_name = true)
GROUP BY ALL
UNION ALL
SELECT 'TOTAL', count(*)
FROM read_parquet('data/raw/*/2026/*.parquet', union_by_name = true)
ORDER BY tipo;
```

- **Objetivo:** contar los registros con `count(*)` y contrastar el resultado con la metadata.
- **Fuente:** los 16 archivos de `data/raw/*/2026/`.
- **Resultado:**

| tipo   | registros  |
|--------|-----------:|
| TOTAL  | 30,040,469 |
| green  | 337,114    |
| yellow | 29,703,355 |

- **Decision:** el conteo coincide con la suma de `num_rows` y con el total del
  manifiesto de la descarga, de modo que el conjunto esta completo. Para contar
  basta la metadata, que es instantanea.

## 3.3 y 3.4 Columnas y tipos de datos

### 04 y 05 - `04_columnas_yellow.sql`, `05_columnas_green.sql`

```sql
DESCRIBE SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true);
DESCRIBE SELECT * FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true);
```

- **Objetivo:** listar las columnas y el tipo logico que DuckDB les asigna.
- **Fuente:** `data/raw/yellow/2026/*.parquet` y `data/raw/green/2026/*.parquet`.
- **Resultado:** yellow tiene 21 columnas y green tiene 22.

| columna | yellow | green |
|---|---|---|
| VendorID, PULocationID, DOLocationID | INTEGER | INTEGER |
| `tpep_pickup_datetime`, `tpep_dropoff_datetime` | TIMESTAMP | - |
| `lpep_pickup_datetime`, `lpep_dropoff_datetime` | - | TIMESTAMP |
| passenger_count, RatecodeID, payment_type | BIGINT | BIGINT |
| trip_type | - | BIGINT |
| trip_distance, fare_amount, extra, mta_tax, tip_amount, tolls_amount, improvement_surcharge, total_amount, congestion_surcharge, cbd_congestion_fee | DOUBLE | DOUBLE |
| Airport_fee | DOUBLE | - |
| ehail_fee | - | DOUBLE |
| store_and_fwd_flag, request_source | VARCHAR | VARCHAR |

- **Decision:**
  - `passenger_count`, `RatecodeID` y `payment_type` vienen como BIGINT, pero
    son categorias o conteos pequenos. Al materializar se pueden convertir a
    tipos mas pequenos.
  - Los montos vienen en DOUBLE. Para agregaciones monetarias exactas convendria
    usar DECIMAL.
  - Para unir ambos tipos de taxi hay que renombrar las columnas de fecha.

### 06 - `06_comparacion_columnas.sql`

```sql
SELECT name AS columna,
       count(DISTINCT file_name) FILTER (WHERE file_name LIKE '%/yellow/%') AS archivos_yellow,
       count(DISTINCT file_name) FILTER (WHERE file_name LIKE '%/green/%') AS archivos_green
FROM parquet_schema('data/raw/*/2026/*.parquet')
WHERE name <> 'schema'
GROUP BY name
ORDER BY archivos_yellow = 0, archivos_green = 0, columna;
```

- **Objetivo:** ver que columnas son comunes, cuales son exclusivas de cada tipo y en cuantos archivos aparece cada una.
- **Fuente:** el esquema de los 16 archivos, leido de su metadata.
- **Resultado:**
  - 17 columnas comunes.
  - Exclusivas de yellow: `tpep_*` y `Airport_fee`.
  - Exclusivas de green: `lpep_*`, `ehail_fee` y `trip_type`.
  - `request_source` aparece solo en 3 de 8 archivos de cada tipo.
- **Decision:** al combinar ambos tipos hay que usar `UNION ALL BY NAME` y
  `union_by_name = true`. `Airport_fee` conserva una mayuscula inicial que no
  sigue la convencion del resto, y conviene normalizarla al materializar.

### 07 - `07_tipos_por_archivo.sql`

```sql
WITH esquema AS (
    SELECT regexp_extract(file_name, 'raw/(\w+)/', 1) AS tipo,
           regexp_extract(file_name, '(\d{4}-\d{2})\.parquet', 1) AS mes,
           name AS columna, type AS tipo_fisico, logical_type
    FROM parquet_schema('data/raw/*/2026/*.parquet')
    WHERE name <> 'schema'
)
SELECT tipo, columna,
       string_agg(DISTINCT tipo_fisico, ', ') AS tipos_fisicos,
       count(*) AS archivos_con_columna,
       string_agg(mes, ', ' ORDER BY mes) AS meses
FROM esquema
GROUP BY tipo, columna
HAVING count(DISTINCT tipo_fisico) > 1 OR count(*) < 8
ORDER BY tipo, columna;
```

- **Objetivo:** detectar si el esquema cambia entre meses, ya sea porque una columna cambia de tipo fisico o porque falta en algun archivo.
- **Fuente:** el esquema de los 16 archivos.
- **Resultado:**

| tipo   | columna        | tipos_fisicos | archivos | meses                     |
|--------|----------------|---------------|---------:|---------------------------|
| green  | request_source | BYTE_ARRAY    | 3        | 2026-06, 2026-07, 2026-08 |
| yellow | request_source | BYTE_ARRAY    | 3        | 2026-06, 2026-07, 2026-08 |

- **Decision:** ninguna columna cambia de tipo entre meses. La unica deriva de
  esquema es `request_source`, que se agrego en junio de 2026. Para enero a
  mayo es `NULL` por construccion, no por falta de datos, y no debe tratarse
  como un faltante.

## 3.5 Muestra de registros

### 08 y 09 - `08_muestra_yellow.sql`, `09_muestra_green.sql`

```sql
SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
USING SAMPLE reservoir(10 ROWS) REPEATABLE (42);
-- igual para green
```

- **Objetivo:** ver registros reales para entender el formato de cada columna. `REPEATABLE (42)` hace la muestra reproducible.
- **Fuente:** `data/raw/yellow/2026/*.parquet` y `data/raw/green/2026/*.parquet`.
- **Resultado:** ver el notebook, que tiene las 10 filas de cada tipo. Lo que se observa:
  - los montos cuadran a simple vista (`fare + extra + mta_tax + tip + tolls + surcharges = total`);
  - `cbd_congestion_fee` es 0.75 en viajes yellow que pasan por Manhattan;
  - en green aparecen filas con `passenger_count`, `RatecodeID`, `payment_type`, `trip_type` y `store_and_fwd_flag` en `NULL` a la vez, y con `VendorID = 6`;
  - `ehail_fee` siempre es `NULL`.
- **Decision:** el patron de nulos simultaneos merece analizarse aparte (consulta 16).

## 3.6 Problemas de calidad de datos

### 10 - `10_nulos.sql`

```sql
-- CTE viajes
SELECT tipo, count(*) AS registros,
       round(100 * count(*) FILTER (WHERE passenger_count IS NULL) / count(*), 2) AS pct_null_passenger_count,
       ... -- igual para RatecodeID, store_and_fwd_flag, congestion_surcharge,
           -- payment_type, trip_type, ehail_fee, request_source
FROM viajes
GROUP BY tipo;
```

- **Objetivo:** medir el porcentaje de nulos por columna.
- **Fuente:** los 16 archivos, a traves del CTE `viajes`.
- **Resultado:**

| tipo   | passenger_count / RatecodeID / store_and_fwd / congestion | payment_type | trip_type | ehail_fee | request_source |
|--------|------:|------:|------:|------:|------:|
| green  | 14.47% | 14.47% | 14.47% | 100% | 94.30% |
| yellow | 25.98% | 0.00%  | (no aplica) | (no aplica) | 90.23% |

- **Decision:**
  - `ehail_fee` esta 100% vacia en green y puede descartarse.
  - En yellow, `trip_type` y `ehail_fee` son `NULL` porque la columna no existe en ese tipo.
  - Que cuatro columnas tengan exactamente el mismo porcentaje de nulos sugiere
    que se trata de las mismas filas. Se investiga en la consulta 16.

### 11 - `11_fechas_fuera_de_rango.sql`

```sql
-- CTE viajes
SELECT tipo,
       count(*) FILTER (WHERE strftime(pickup, '%Y-%m') <> mes_archivo) AS fuera_del_mes,
       count(*) FILTER (WHERE year(pickup) <> 2026) AS fuera_de_2026,
       min(pickup) AS pickup_min,
       max(pickup) AS pickup_max
FROM viajes
GROUP BY tipo;
```

- **Objetivo:** encontrar viajes cuya fecha de inicio no corresponde al mes del archivo que los contiene.
- **Fuente:** los 16 archivos. El mes del archivo sale del nombre, gracias a `filename = true`.
- **Resultado:**

| tipo   | fuera_del_mes | fuera_de_2026 | pickup_min          | pickup_max          |
|--------|--------------:|--------------:|---------------------|---------------------|
| green  | 98            | 14            | 2008-12-31 17:35:31 | 2026-08-31 23:58:28 |
| yellow | 146           | 17            | 2001-01-01 09:23:58 | 2026-08-31 23:59:59 |

- **Decision:** son pocos registros (0.0005% en yellow y 0.03% en green), pero distorsionan
  cualquier analisis temporal, como `min()` o las series por mes. Hay que
  filtrar por el mes del archivo o por el rango de 2026 antes de agregar por
  fecha.

### 12 - `12_duraciones_anomalas.sql`

```sql
-- CTE viajes
SELECT tipo,
       count(*) FILTER (WHERE dropoff < pickup) AS dropoff_antes_pickup,
       count(*) FILTER (WHERE dropoff = pickup) AS duracion_cero,
       count(*) FILTER (WHERE dropoff - pickup > INTERVAL 24 HOUR) AS mas_de_24h,
       max(dropoff - pickup) AS duracion_max
FROM viajes
GROUP BY tipo;
```

- **Objetivo:** detectar duraciones imposibles (negativas) o sospechosas (cero, o mas de un dia).
- **Fuente:** los 16 archivos.
- **Resultado:**

| tipo   | dropoff_antes_pickup | duracion_cero | mas_de_24h | duracion_max     |
|--------|---------------------:|--------------:|-----------:|------------------|
| green  | 5                    | 229           | 4          | 1 day 16:56:22   |
| yellow | 10                   | 371,673       | 263        | 11 days 22:05:25 |

- **Decision:** los viajes con duracion negativa o de mas de 24 h se excluyen de
  cualquier calculo de duracion o velocidad. Los de duracion cero (1.25% en
  yellow) probablemente son viajes cancelados y deben filtrarse en los
  indicadores de viajes efectivos.

### 13 - `13_distancias_y_montos.sql`

```sql
-- CTE viajes
SELECT tipo,
       count(*) FILTER (WHERE trip_distance = 0) AS distancia_cero,
       count(*) FILTER (WHERE trip_distance > 200) AS distancia_mayor_200mi,
       max(trip_distance) AS distancia_max,
       count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa,
       count(*) FILTER (WHERE total_amount < 0) AS total_negativo,
       count(*) FILTER (WHERE total_amount > 1000) AS total_mayor_1000,
       min(total_amount) AS total_min,
       max(total_amount) AS total_max
FROM viajes
GROUP BY tipo;
```

- **Objetivo:** detectar distancias y montos fuera de lo razonable.
- **Fuente:** los 16 archivos.
- **Resultado:**

| tipo   | dist = 0 | dist > 200 mi | dist max   | tarifa < 0 | total < 0 | total > 1000 | total min | total max |
|--------|---------:|--------------:|-----------:|-----------:|----------:|-------------:|----------:|----------:|
| green  | 12,212   | 69            | 179,830.92 | 999        | 1,023     | 1            | -501.50   | 1,678.20  |
| yellow | 952,231  | 704           | 328,522.20 | 157,364    | 161,835   | 49           | -2,560.20 | 7,053.50  |

- **Decision:**
  - Las distancias de cientos de miles de millas son errores del taximetro, y
    los viajes de mas de 200 mi se excluyen de los analisis de distancia.
  - Los montos negativos (0.54% en yellow) son reembolsos o ajustes. Se
    excluyen de los ingresos promedio, o se analizan por separado.
  - Los viajes con distancia cero (3.2% en yellow) se tratan igual que los de
    duracion cero.

### 14 - `14_codigos_invalidos.sql`

```sql
-- CTE viajes
SELECT tipo,
       count(*) FILTER (WHERE passenger_count = 0) AS pasajeros_cero,
       count(*) FILTER (WHERE passenger_count > 6) AS pasajeros_mas_de_6,
       count(*) FILTER (WHERE RatecodeID NOT BETWEEN 1 AND 6) AS ratecode_fuera_dic,
       count(*) FILTER (WHERE payment_type NOT BETWEEN 0 AND 6) AS payment_fuera_dic,
       count(*) FILTER (WHERE payment_type = 0) AS payment_cero,
       count(*) FILTER (WHERE PULocationID NOT BETWEEN 1 AND 263
                           OR DOLocationID NOT BETWEEN 1 AND 263) AS zona_desconocida,
       list_sort(list(DISTINCT VendorID)) AS vendor_ids
FROM viajes
GROUP BY tipo;
```

- **Objetivo:** validar las columnas categoricas contra el diccionario de datos
  de la TLC:
  - RatecodeID va de 1 a 6;
  - payment_type va de 0 a 6;
  - las zonas 264 y 265 significan "Unknown" y "Outside of NYC".
- **Fuente:** los 16 archivos.
- **Resultado:**

| tipo   | pasajeros = 0 | pasajeros > 6 | RatecodeID fuera | payment fuera | payment = 0 | zona desconocida | VendorID     |
|--------|--------------:|--------------:|-----------------:|--------------:|------------:|-----------------:|--------------|
| green  | 4,527         | 99            | 2                | 0             | 0           | 5,886            | [1, 2, 6]    |
| yellow | 91,359        | 28            | 769,693          | 0             | 7,716,688   | 201,486          | [1, 2, 6, 7] |

- **Decision:**
  - `RatecodeID = 99` (consulta 17) indica una tarifa desconocida y se trata como `NULL`.
  - Los viajes con 0 pasajeros o mas de 6 se marcan como dudosos.
  - Las zonas 264 y 265 se excluyen de los analisis geograficos.
  - `payment_type = 0` se investiga en la consulta 16.

### 15 - `15_duplicados.sql`

```sql
WITH yellow AS (
    SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
), green AS (
    SELECT * FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
)
SELECT 'yellow' AS tipo, count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM yellow)) AS filas_duplicadas
FROM yellow
UNION ALL
SELECT 'green', count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM green))
FROM green;
```

- **Objetivo:** contar las filas que son exactamente iguales a otra en todas sus columnas.
- **Fuente:** los 16 archivos, por tipo.
- **Resultado:** 7 filas duplicadas en yellow y 0 en green.
- **Decision:** la cantidad es despreciable, pero se eliminaran con `DISTINCT`
  al materializar, para no contar dos veces el mismo viaje.

### 16 - `16_patron_nulos.sql`

```sql
-- CTE viajes
SELECT tipo, VendorID, payment_type, RatecodeID,
       count(*) AS registros,
       count(*) FILTER (WHERE store_and_fwd_flag IS NULL AND congestion_surcharge IS NULL) AS tambien_nulos
FROM viajes
WHERE passenger_count IS NULL
GROUP BY ALL
ORDER BY registros DESC
LIMIT 10;
```

- **Objetivo:** perfilar los registros con `passenger_count` nulo.
- **Fuente:** los 16 archivos.
- **Resultado:**

| tipo   | VendorID | payment_type | RatecodeID | registros | tambien_nulos |
|--------|---------:|-------------:|-----------:|----------:|--------------:|
| yellow | 2        | 0            | NULL       | 6,761,917 | 6,761,917     |
| yellow | 1        | 0            | NULL       | 895,381   | 895,381       |
| yellow | 6        | 0            | NULL       | 59,390    | 59,390        |
| green  | 6        | NULL         | NULL       | 34,847    | 34,847        |
| green  | 2        | NULL         | NULL       | 13,400    | 13,400        |
| green  | 1        | NULL         | NULL       | 528       | 528           |

- **Decision:**
  - Los nulos no son aleatorios: siempre coinciden en las mismas filas.
  - En yellow corresponden exactamente a los 7,716,688 viajes con
    `payment_type = 0`, que el diccionario describe como "Flex Fare trip".
    Estos viajes se reportan sin los campos del taximetro, asi que no hay que
    imputarlos. Se tratan como un segmento propio y se excluyen de los analisis
    de pasajeros y de tarifa.
  - En green, la mayoria provienen de `VendorID = 6` (Myle Technologies).

### 17 - `17_ratecode_payment.sql`

```sql
-- CTE viajes
SELECT tipo, 'RatecodeID' AS columna, RatecodeID AS valor, count(*) AS registros
FROM viajes GROUP BY ALL
UNION ALL
SELECT tipo, 'payment_type', payment_type, count(*)
FROM viajes GROUP BY ALL
ORDER BY tipo, columna, valor NULLS LAST;
```

- **Objetivo:** ver la distribucion completa de los dos codigos categoricos principales.
- **Fuente:** los 16 archivos.
- **Resultado:**
  - Yellow:
    - RatecodeID: el 67.7% es `1` (tarifa estandar), 769,693 filas son `99` y 7,716,688 son `NULL`.
    - payment_type: 63.8% tarjeta (1), 9.1% efectivo (2) y 26.0% Flex Fare (0).
  - Green:
    - RatecodeID: 2 filas son `99` y 48,775 son `NULL`.
    - payment_type: no hay valores `0`.
- **Decision:** se confirma que `99` es el unico codigo fuera del diccionario, y
  se recodifica como `NULL`. Las proporciones de pago deben calcularse
  excluyendo o separando la categoria `0`.

## Resumen de decisiones

1. Usar `union_by_name = true` y `UNION ALL BY NAME`, porque el esquema varia
   entre tipos y entre meses (`request_source`).
2. Renombrar `tpep_*` y `lpep_*` a `pickup`/`dropoff` para trabajar con ambos tipos.
3. Filtrar los viajes cuya fecha de inicio no cae en el mes del archivo.
4. Excluir duraciones negativas o de mas de 24 h, y distancias de mas de 200 mi.
5. Tratar por separado los montos negativos y los viajes Flex Fare (`payment_type = 0`).
6. Recodificar `RatecodeID = 99` como `NULL` y descartar `ehail_fee`.
7. Eliminar los 7 duplicados exactos de yellow.

Ninguna de estas decisiones modifica los archivos originales en `data/raw/`.
Se aplicaran en las etapas posteriores de preparacion de datos.

---

## 3.9 Que significa consultar directamente un archivo Parquet

Consultar directamente un archivo Parquet significa que el motor (DuckDB) lee
los archivos donde estan, con `read_parquet('ruta/*.parquet')`, como si fueran
una tabla. No hace falta un paso previo de `CREATE TABLE` + `INSERT` o `COPY`.
Los datos nunca se copian a una base de datos: cada consulta va al archivo,
lee lo que necesita y descarta el resto.

Esta estrategia es util cuando el volumen es grande por varias razones:

- **Formato columnar.** Parquet guarda cada columna por separado y comprimida.
  Si una consulta usa 3 de 21 columnas, solo se leen esas 3 (proyeccion de
  columnas). En este laboratorio, 30 millones de filas ocupan unos 520 MB en
  disco.
- **Metadata y estadisticas.** El footer de cada archivo guarda la cantidad de
  filas, el esquema y los valores minimo y maximo por row group. Por eso
  `parquet_file_metadata` y `parquet_schema` respondieron al instante sin leer
  datos, y un filtro como `WHERE pickup >= '2026-06-01'` puede saltarse row
  groups enteros (filter pushdown).
- **Sin duplicar almacenamiento ni tiempo de carga.** No existe una segunda
  copia de los datos en una base de datos, y la primera consulta empieza de
  inmediato, sin esperar una importacion.
- **Procesamiento en streaming y en paralelo.** DuckDB procesa los archivos por
  bloques y en varios hilos, de modo que puede analizar conjuntos mas grandes
  que la memoria RAM disponible.
- **Glob y multiples archivos.** Un patron como `data/raw/*/2026/*.parquet`
  trata los 16 archivos como una sola fuente. Al publicarse un mes nuevo basta
  con descargarlo, sin recargar nada.
- **Exploracion barata.** Permite conocer los datos (esquema, calidad, volumen)
  antes de decidir que se materializa y como, que es justo el objetivo de esta
  fase.

La contrapartida es que cada consulta vuelve a leer y descomprimir los archivos.
Para consultas repetitivas sobre el mismo subconjunto conviene materializar una
tabla en un archivo `.duckdb`, lo que se evalua en ejercicios posteriores.
