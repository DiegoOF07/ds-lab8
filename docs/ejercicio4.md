# Ejercicio 4 - Analisis exploratorio con DuckDB

Todas las consultas se ejecutan con DuckDB 1.5.5 directamente sobre los archivos
Parquet de `data/raw/`, igual que en el Ejercicio 3: no se crea ninguna tabla.
Cada consulta esta en `sql/ejercicio4/` y el notebook
`notebooks/02_analisis_exploratorio.ipynb` las ejecuta en orden, muestra los
resultados y genera las graficas.

Los resultados corresponden a los datos publicados por la TLC al 7 de octubre
de 2026: enero a agosto de 2026, yellow y green (16 archivos, 30,040,469
registros).

## Como ejecutar

```bash
# Descargar los datos (si no se ha hecho) y la tabla de zonas
docker compose exec lab python scripts/download_data.py

# Ejecutar el notebook completo y guardar las salidas (tarda unos 2 minutos)
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/02_analisis_exploratorio.ipynb
```

Para ejecutar una consulta suelta hay que crear antes las vistas en la misma
conexion:

```bash
docker compose exec lab python -c "
import duckdb; con = duckdb.connect()
con.execute(open('sql/ejercicio4/00_vistas.sql').read())
print(con.sql(open('sql/ejercicio4/01_viajes_por_mes.sql').read()))"
```

## Fuentes

| Fuente | Ruta | Uso |
|---|---|---|
| Viajes yellow | `data/raw/yellow/*/*.parquet` | todas las consultas, a traves de las vistas |
| Viajes green | `data/raw/green/*/*.parquet` | todas las consultas, a traves de las vistas |
| Zonas TLC | `data/raw/taxi_zone_lookup.csv` | consultas 06 y 07 |

La tabla de zonas traduce `PULocationID`/`DOLocationID` (1 a 265) a borough,
nombre de zona y `service_zone`. Esta ultima columna distingue la **Yellow Zone**
(Manhattan al sur de la calle 96 Este / 110 Oeste, donde solo los taxis
amarillos pueden recoger pasajeros en la calle), la **Boro Zone** (resto de la
ciudad, donde operan los taxis verdes) y los aeropuertos. Se agrego su descarga
a `scripts/download_data.py` para que el analisis sea reproducible sin pasos
manuales.

---

## Vistas comunes (`00_vistas.sql`)

En lugar de repetir el CTE de union en cada consulta, como en el Ejercicio 3,
se definen tres vistas que las 17 consultas reutilizan. Una vista solo guarda
la consulta: cada vez que se usa, DuckDB vuelve a leer los Parquet, de modo
que se sigue consultando directamente sobre los archivos.

```sql
CREATE OR REPLACE VIEW viajes AS
WITH base AS (
    SELECT 'yellow' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           tpep_pickup_datetime AS pickup, tpep_dropoff_datetime AS dropoff, *
               EXCLUDE (tpep_pickup_datetime, tpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/yellow/*/*.parquet', filename = true, union_by_name = true)
    UNION ALL BY NAME
    SELECT 'green' AS tipo, regexp_extract(filename, '(\d{4}-\d{2})\.parquet', 1) AS mes_archivo,
           lpep_pickup_datetime AS pickup, lpep_dropoff_datetime AS dropoff, *
               EXCLUDE (lpep_pickup_datetime, lpep_dropoff_datetime, filename)
    FROM read_parquet('data/raw/green/*/*.parquet', filename = true, union_by_name = true)
)
SELECT * REPLACE (nullif(RatecodeID, 99) AS RatecodeID),
       year(pickup) AS anio, month(pickup) AS mes, hour(pickup) AS hora,
       isodow(pickup) AS dia_semana,                      -- 1 = lunes ... 7 = domingo
       CASE WHEN VendorID = 7 AND dropoff = pickup THEN NULL
            ELSE epoch(dropoff - pickup) / 60 END AS duracion_min,
       CASE payment_type WHEN 0 THEN 'Flex Fare' WHEN 1 THEN 'Tarjeta' WHEN 2 THEN 'Efectivo'
                         WHEN 3 THEN 'Sin cargo' WHEN 4 THEN 'Disputa' WHEN 5 THEN 'Desconocido'
                         WHEN 6 THEN 'Anulado' ELSE 'Sin dato' END AS forma_pago,
       strftime(pickup, '%Y-%m') = mes_archivo AS ok_fecha,
       (dropoff > pickup AND dropoff - pickup <= INTERVAL 24 HOUR)
           OR (VendorID = 7 AND dropoff = pickup) AS ok_duracion,
       trip_distance > 0 AND trip_distance <= 200 AS ok_distancia,
       fare_amount >= 0 AND total_amount >= 0 AS ok_monto
FROM base;

CREATE OR REPLACE VIEW viajes_validos AS
SELECT * FROM viajes
WHERE ok_fecha AND ok_duracion AND ok_distancia AND ok_monto;

CREATE OR REPLACE VIEW zonas AS
SELECT LocationID, Borough AS borough, Zone AS zona, service_zone
FROM read_csv('data/raw/taxi_zone_lookup.csv', header = true);
```

| Vista | Contenido | Se usa en |
|---|---|---|
| `viajes` | todos los registros, con columnas derivadas y una bandera `ok_*` por regla de calidad | 14 y 16, que miden la calidad |
| `viajes_validos` | solo los registros que cumplen las cuatro reglas | el resto del analisis |
| `zonas` | tabla de zonas de la TLC | 06 y 07 |

Las reglas aplican las decisiones del Ejercicio 3:

| Bandera | Regla | Origen |
|---|---|---|
| `ok_fecha` | el pickup cae en el mes del archivo | Ej. 3, consulta 11 |
| `ok_duracion` | duracion positiva y de 24 h o menos | Ej. 3, consulta 12, **ajustada en este ejercicio (P16)** |
| `ok_distancia` | distancia mayor que 0 y de 200 mi o menos | Ej. 3, consulta 13 |
| `ok_monto` | tarifa y total no negativos | Ej. 3, consulta 13 |

Ademas, `RatecodeID = 99` se recodifica como `NULL` (Ej. 3, consulta 17). Los
viajes Flex Fare no se excluyen, sino que se identifican con `forma_pago`. Los 7
duplicados de yellow tampoco se eliminan: un `DISTINCT *` sobre 30 millones de
filas haria lentas todas las consultas para corregir 7 registros. Se eliminaran
al materializar la tabla (Ejercicio 6).

El ajuste de `ok_duracion` sale de la consulta 16 de este ejercicio: VendorID 7
(Helix) no registra la hora de bajada, por lo que su duracion se trata como un
dato faltante y no como un viaje invalido. El detalle esta en P16.

El glob `*/*.parquet` toma todos los anios descargados, y las consultas temporales
agrupan por `anio` y `mes`. Esto prepara el analisis para el Ejercicio 5. Los
resultados de este documento y las salidas guardadas en el notebook se
calcularon cuando solo existia 2026. Si se vuelve a ejecutar el notebook con
mas anios descargados, las consultas que no agrupan por `anio` mezclan los
anios (ver `docs/ejercicio5.md`, seccion 5.7).

El archivo empieza con dos `SET` que limitan los temporales de DuckDB a 4 GB y
los escriben en `data/processed/duckdb_tmp/`. Se agregaron en el Ejercicio 5,
despues de que una consulta sobre 2024 y 2026 escribiera mas de 8 GB de
temporales dentro del disco virtual de Docker.

---

## 4.1 Preguntas planteadas

Las preguntas salen de lo observado en el Ejercicio 3. Ahi se vio que yellow
tiene casi 90 veces mas viajes que green, que una cuarta parte de yellow
corresponde a un segmento (Flex Fare) sin datos de taximetro y que hay montos,
duraciones y distancias imposibles. A eso se sumo una exploracion previa que
mostro que `request_source` trae codigos de licencias de Uber y Lyft.

| # | Pregunta | Eje | Justificacion |
|---|---|---|---|
| P1 | Como evoluciona la demanda mes a mes? | Temporal | Hay 8 meses de 2026; sirve para detectar estacionalidad y si green y yellow siguen la misma tendencia. |
| P2 | En que dias y horas se concentran los viajes? | Temporal | `pickup` tiene precision de segundos; el patron semanal revela para que se usa cada tipo de taxi. |
| P3 | Como se distribuyen distancia, duracion, monto y velocidad? | Distribucion | Son las variables continuas principales. El Ej. 3 mostro maximos absurdos, asi que hay que ver percentiles y no solo promedios. |
| P4 | Como cambia la velocidad a lo largo del dia? | Caracteristicas | La velocidad (distancia / duracion) mide la congestion, que no esta en ninguna columna. |
| P5 | Cuantos pasajeros lleva cada viaje? | Caracteristicas | `passenger_count` tiene 25% de nulos y valores 0; hay que saber que tan util es. |
| P6 | Donde se originan los viajes de cada tipo? | Yellow vs green | Green fue creado para dar servicio fuera del centro de Manhattan; se puede verificar con `service_zone`. |
| P7 | Cuales son las zonas de origen mas frecuentes? | Yellow vs green | Complementa P6 a nivel de zona. |
| P8 | Cuanto pesan los viajes de aeropuerto? | Caracteristicas / pago | Son viajes largos con tarifa propia (`RatecodeID` 2 y 3, `Airport_fee`). |
| P9 | Como se paga cada tipo de taxi? | Pago | `payment_type` tiene una categoria nueva (0, Flex Fare) que el Ej. 3 dejo pendiente. |
| P10 | Como evoluciona el peso de Flex Fare? | Pago / temporal | Ver si Flex Fare es estable, crece o depende del proveedor. |
| P11 | De donde provienen los viajes Flex Fare? | Pago | `request_source` aparece en junio de 2026 y puede explicar el segmento. |
| P12 | Cuanta propina se deja con tarjeta? | Pago | La propina solo se registra en pagos con tarjeta; su distribucion muestra el efecto de las sugerencias de pantalla. |
| P13 | Cuadra el monto total con sus componentes? | Inconsistencias | `total_amount` deberia ser la suma de las columnas de cargos; si no cuadra, alguna columna no significa lo que parece. |
| P14 | Cuantos registros excluyen las reglas de calidad? | Atipicos | Cuantifica cuanto del conjunto se pierde con las reglas del Ej. 3. |
| P15 | Que valores son atipicos dentro de los viajes validos? | Atipicos / distribucion | Distingue colas naturales (viajes largos) de errores que pasaron los filtros. |
| P16 | Que proveedores generan los viajes con duracion cero? | Inconsistencias | El Ej. 3 supuso que eran cancelaciones; hay que confirmarlo. |
| P17 | Los viajes de 3 a 6 pasajeros en green son viajes de grupo? | Inconsistencias | P5 mostro mas viajes de 5 y 6 pasajeros que de 3 y 4 en green. |

---

## 4.2 a 4.4 Consultas, resultados e interpretacion

Salvo que se indique otra cosa, cada consulta lee `viajes_validos`, es decir,
los 16 Parquet de `data/raw/<tipo>/2026/` despues de aplicar las reglas de
calidad: 28,603,548 viajes yellow y 324,161 green.

### 1. Comportamiento temporal

#### P1 - `01_viajes_por_mes.sql`

```sql
SELECT tipo, anio, mes,
       count(*) AS viajes,
       round(count(*) / day(last_day(make_date(anio, mes, 1))), 0) AS viajes_por_dia,
       round(sum(total_amount) / 1e6, 2) AS ingresos_musd,
       round(avg(total_amount), 2) AS total_promedio
FROM viajes_validos
GROUP BY tipo, anio, mes
ORDER BY tipo, anio, mes;
```

- **Objetivo:** medir el volumen y los ingresos de cada mes. Se divide entre los
  dias del mes para que febrero (28 dias) sea comparable con los demas.
- **Resultado:**

| mes | yellow viajes/dia | yellow ingresos (M USD) | yellow total prom. | green viajes/dia | green ingresos (M USD) | green total prom. |
|---|---:|---:|---:|---:|---:|---:|
| 2026-01 | 114,900 | 105.50 | 29.62 | 1,254 | 0.95 | 24.31 |
| 2026-02 | 116,119 | 98.85 | 30.40 | 1,282 | 0.88 | 24.39 |
| 2026-03 | 122,960 | 115.17 | 30.21 | 1,377 | 1.07 | 25.04 |
| 2026-04 | 124,145 | 111.93 | 30.05 | 1,418 | 1.09 | 25.51 |
| 2026-05 | 127,889 | 120.96 | 30.51 | 1,396 | 1.12 | 25.87 |
| 2026-06 | 123,214 | 112.96 | 30.56 | 1,419 | 1.12 | 26.24 |
| 2026-07 | 109,309 | 102.00 | 30.10 | 1,275 | 1.04 | 26.28 |
| 2026-08 | 103,376 | 96.49 | 30.11 | 1,252 | 1.03 | 26.51 |

- **Interpretacion:**
  - Ambos tipos crecen de enero a mayo-junio y caen en julio y agosto. En
    yellow, la caida es mas fuerte: agosto tiene 19% menos viajes por dia que
    mayo y queda 10% por debajo de enero. Green vuelve a su nivel de enero. La
    caida de verano coincide con vacaciones y menor actividad de oficinas en
    Manhattan, que es donde opera yellow (P6).
  - El monto promedio de green sube todos los meses, de 24.31 a 26.51 USD (+9%),
    mientras que el de yellow se mantiene en torno a 30 USD.
  - En 8 meses, yellow genero 863.9 M USD y green 8.3 M USD. Green representa
    el 1.1% de los viajes y el 1.0% de los ingresos.

#### P2 - `02_hora_dia_semana.sql`

```sql
SELECT tipo, dia_semana, hora,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 3) AS pct_del_tipo
FROM viajes_validos
GROUP BY tipo, dia_semana, hora
ORDER BY tipo, dia_semana, hora;
```

- **Objetivo:** ver en que franja de la semana ocurre cada viaje. Se usa el
  porcentaje del total de cada tipo para que yellow y green sean comparables.
- **Resultado:** 168 filas por tipo; el notebook las muestra como mapa de calor.
  Agregando las celdas:

| indicador | yellow | green |
|---|---:|---:|
| viajes en fin de semana | 29.2% | 23.4% |
| entre semana, 7 a 9 h | 13.5% | 17.7% |
| entre semana, 20 a 23 h | 22.8% | 12.4% |
| fin de semana, 0 a 4 h (de los viajes de fin de semana) | 17.8% | 9.8% |
| celda con mas viajes | jueves 21 h | jueves 17 h |

- **Interpretacion:** green es un taxi de traslados laborales. Tiene picos
  marcados en la manana (7 a 9 h) y la tarde (16 a 18 h) de lunes a viernes, y
  cae de noche. Yellow tiene un pico de tarde menos marcado, mantiene mucha
  demanda hasta las 23 h y concentra la vida nocturna: los sabados y domingos
  entre 0 y 4 h tiene casi el doble de peso relativo que green.

### 2. Caracteristicas de los viajes

#### P3 - `03_distribucion_viajes.sql`

```sql
WITH metricas AS (
    SELECT tipo, trip_distance AS distancia_mi, duracion_min,
           total_amount AS total_usd, trip_distance / (duracion_min / 60) AS velocidad_mph
    FROM viajes_validos
), largo AS (
    UNPIVOT metricas ON distancia_mi, duracion_min, total_usd, velocidad_mph
    INTO NAME metrica VALUE valor
), resumen AS (
    SELECT tipo, metrica, avg(valor) AS promedio,
           quantile_cont(valor, [0.05, 0.25, 0.5, 0.75, 0.95, 0.99]) AS q,
           max(valor) AS maximo
    FROM largo GROUP BY ALL
)
SELECT tipo, metrica, round(promedio, 2) AS promedio,
       round(q[1], 2) AS p05, round(q[2], 2) AS p25, round(q[3], 2) AS mediana,
       round(q[4], 2) AS p75, round(q[5], 2) AS p95, round(q[6], 2) AS p99,
       round(maximo, 2) AS maximo
FROM resumen ORDER BY metrica, tipo;
```

- **Objetivo:** describir la forma de la distribucion de las cuatro variables
  continuas. `UNPIVOT` las pone en formato largo para calcularlas con una sola
  agregacion. Los `NULL` (duracion de Helix) quedan fuera automaticamente.
- **Resultado:**

| metrica | tipo | promedio | p05 | p25 | mediana | p75 | p95 | p99 | maximo |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| distancia (mi) | green | 3.36 | 0.63 | 1.33 | 2.15 | 3.78 | 10.67 | 17.81 | 134.49 |
| distancia (mi) | yellow | 3.51 | 0.50 | 1.10 | 1.92 | 3.93 | 12.52 | 19.55 | 199.30 |
| duracion (min) | green | 21.26 | 4.15 | 8.68 | 13.35 | 20.73 | 45.22 | 82.72 | 1,439.80 |
| duracion (min) | yellow | 17.95 | 4.02 | 8.62 | 14.12 | 22.27 | 44.13 | 71.70 | 1,439.93 |
| total (USD) | green | 25.54 | 9.70 | 15.12 | 20.52 | 29.70 | 56.84 | 96.00 | 1,678.20 |
| total (USD) | yellow | 30.20 | 12.40 | 17.45 | 23.58 | 34.43 | 77.20 | 104.96 | 7,053.50 |
| velocidad (mph) | green | 15.65 | 5.18 | 7.93 | 10.04 | 13.12 | 22.83 | 34.28 | 82,272.00 |
| velocidad (mph) | yellow | 11.10 | 3.94 | 6.83 | 9.28 | 12.93 | 24.11 | 34.46 | 68,940.00 |

- **Interpretacion:**
  - Las cuatro variables tienen asimetria a la derecha: el promedio supera a
    la mediana y el p99 esta muy lejos del p75. El viaje tipico es corto (unas
    2 mi y 14 min), pero hay una cola larga de viajes al aeropuerto (P8). Por
    eso el resto del analisis usa medianas.
  - Green recorre algo mas de distancia que yellow en la mediana (2.15 frente
    a 1.92 mi), pero cobra menos (20.52 frente a 23.58 USD). Yellow paga
    recargos propios del centro de Manhattan, como `congestion_surcharge` y
    `cbd_congestion_fee`.
  - Los maximos siguen siendo imposibles aunque pasaron las reglas de calidad:
    velocidades de decenas de miles de mph y duraciones al limite de 24 h. Se
    analizan en P15.

#### P4 - `04_velocidad_por_hora.sql`

```sql
SELECT tipo, hora,
       count(*) AS viajes,
       round(median(trip_distance / (duracion_min / 60)), 1) AS velocidad_mediana_mph,
       round(median(duracion_min), 1) AS duracion_mediana_min,
       round(median(trip_distance), 2) AS distancia_mediana_mi
FROM viajes_validos
WHERE dia_semana <= 5          -- lunes a viernes
  AND duracion_min >= 1        -- evita velocidades infladas por duraciones de segundos
GROUP BY ALL
ORDER BY tipo, hora;
```

- **Objetivo:** usar la velocidad como indicador de congestion en dias
  laborales. Se usa la mediana, que no se ve afectada por los valores imposibles
  de P3.
- **Resultado (seleccion de horas, yellow):**

| hora | viajes | velocidad mediana (mph) | duracion mediana (min) | distancia mediana (mi) |
|---:|---:|---:|---:|---:|
| 4 | 102,364 | 16.8 | 14.7 | 4.26 |
| 8 | 985,402 | 8.8 | 14.6 | 1.96 |
| 11 | 938,302 | 7.3 | 15.9 | 1.68 |
| 15 | 1,209,602 | 7.4 | 15.6 | 1.67 |
| 18 | 1,317,801 | 8.1 | 13.2 | 1.55 |
| 22 | 1,163,814 | 10.5 | 14.0 | 2.27 |

  En green, la velocidad va de 18.4 mph a las 4 h a 8.6 mph a las 15 h.

- **Interpretacion:**
  - Entre las 10 y las 17 h, yellow circula a menos de 8 mph (unos 12 km/h),
    menos de la mitad que de madrugada. Green es mas rapido durante el dia
    (8.6 a 9.7 mph) porque opera fuera del centro de Manhattan.
  - La duracion mediana casi no cambia en todo el dia (12.8 a 15.9 min), pero la
    distancia si: a las 4 h el viaje mediano mide 4.26 mi y a las 18 h, 1.55
    mi. Los pasajeros parecen tolerar un tiempo de viaje mas o menos fijo, y
    con trafico recorren menos distancia en ese tiempo.

#### P5 - `05_pasajeros.sql`

```sql
SELECT tipo,
       CASE WHEN passenger_count IS NULL THEN 'sin dato'
            WHEN passenger_count >= 7 THEN '7+'
            ELSE passenger_count::VARCHAR END AS pasajeros,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_del_tipo
FROM viajes_validos
GROUP BY tipo, pasajeros
ORDER BY tipo, pasajeros;
```

- **Resultado:**

| pasajeros | yellow | green |
|---|---:|---:|
| 0 | 0.31% | 1.32% |
| 1 | 62.01% | 70.61% |
| 2 | 9.27% | 8.48% |
| 3 | 2.09% | 0.96% |
| 4 | 1.37% | 0.70% |
| 5 | 0.20% | 1.90% |
| 6 | 0.12% | 1.31% |
| 7+ | 0.00% | 0.02% |
| sin dato | 24.63% | 14.71% |

- **Interpretacion:** entre los viajes con dato, el 82% lleva un solo pasajero
  en ambos tipos (82.3% en yellow y 82.8% en green). La falta de dato coincide
  con Flex Fare en yellow (P9) y con los viajes de aplicacion en green (P11).
  En green, 5 y 6 pasajeros aparecen mas que 3 y 4, lo que no es esperable y
  se investiga en P17.

### 3. Diferencias entre taxis amarillos y verdes

#### P6 - `06_zonas_servicio.sql`

```sql
SELECT v.tipo, z.borough, z.service_zone,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo), 2) AS pct_del_tipo
FROM viajes_validos v
JOIN zonas z ON v.PULocationID = z.LocationID
GROUP BY v.tipo, z.borough, z.service_zone
ORDER BY v.tipo, viajes DESC;
```

- **Fuentes:** `viajes_validos` y `zonas`.
- **Resultado (% de los viajes de cada tipo segun su origen):**

| borough - service_zone | yellow | green |
|---|---:|---:|
| Manhattan - Yellow Zone | 83.23 | 6.95 |
| Queens - Airports | 6.51 | 0.04 |
| Brooklyn - Boro Zone | 3.56 | 15.82 |
| Manhattan - Boro Zone | 3.49 | 52.50 |
| Queens - Boro Zone | 2.30 | 22.01 |
| Bronx - Boro Zone | 0.77 | 2.49 |
| Staten Island, EWR y desconocidas | 0.13 | 0.20 |

- **Interpretacion:**
  - Los dos tipos operan en mercados casi disjuntos. El 83% de yellow sale de
    la Yellow Zone y un 6.5% de los aeropuertos. Green sale en un 93% de la
    Boro Zone: norte de Manhattan, Queens y Brooklyn.
  - El 6.95% de green que figura en la Yellow Zone se concentra en zonas
    limitrofes con su area de servicio, como Central Park (P7). Las zonas de la
    TLC no coinciden exactamente con las calles 96 y 110, asi que con estos
    datos no se puede afirmar que se trate de recogidas indebidas.
  - Green casi no recoge en aeropuertos (0.04%), lo que es coherente con la
    regulacion, que no se lo permite.

#### P7 - `07_top_zonas.sql`

```sql
SELECT v.tipo,
       row_number() OVER (PARTITION BY v.tipo ORDER BY count(*) DESC) AS posicion,
       z.borough, z.zona, z.service_zone,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo), 2) AS pct_del_tipo
FROM viajes_validos v
JOIN zonas z ON v.PULocationID = z.LocationID
GROUP BY v.tipo, z.borough, z.zona, z.service_zone
QUALIFY posicion <= 10
ORDER BY v.tipo, posicion;
```

- **Resultado (top 5):**

| # | yellow | % | green | % |
|---:|---|---:|---|---:|
| 1 | Upper East Side South | 4.47 | East Harlem North | 26.95 |
| 2 | Midtown Center | 4.16 | East Harlem South | 12.96 |
| 3 | Upper East Side North | 3.99 | Forest Hills (Queens) | 4.86 |
| 4 | JFK Airport | 3.97 | Central Park | 4.02 |
| 5 | Penn Station/Madison Sq West | 3.09 | Morningside Heights | 3.86 |

- **Interpretacion:** yellow esta repartido entre muchas zonas del centro, y
  ninguna supera el 4.5%. Green esta muy concentrado: East Harlem (norte y sur)
  genera el 40% de sus viajes, y las 10 primeras zonas suman el 68%.

#### P8 - `08_aeropuertos.sql`

```sql
SELECT tipo,
       CASE WHEN 132 IN (PULocationID, DOLocationID) THEN 'JFK'
            WHEN 138 IN (PULocationID, DOLocationID) THEN 'LaGuardia'
            WHEN 1 IN (PULocationID, DOLocationID) THEN 'Newark'
            ELSE 'Sin aeropuerto' END AS aeropuerto,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_viajes,
       round(100 * sum(total_amount) / sum(sum(total_amount)) OVER (PARTITION BY tipo), 2) AS pct_ingresos,
       round(median(trip_distance), 2) AS distancia_mediana_mi,
       round(median(duracion_min), 1) AS duracion_mediana_min,
       round(median(total_amount), 2) AS total_mediano
FROM viajes_validos
GROUP BY tipo, aeropuerto
ORDER BY tipo, viajes DESC;
```

- **Objetivo:** medir el peso de los viajes que salen de un aeropuerto o llegan
  a uno (zonas 132, 138 y 1).
- **Resultado:**

| tipo | aeropuerto | % viajes | % ingresos | distancia med. (mi) | total med. (USD) |
|---|---|---:|---:|---:|---:|
| yellow | Sin aeropuerto | 91.85 | 78.96 | 1.77 | 22.39 |
| yellow | JFK | 4.64 | 12.51 | 16.90 | 89.21 |
| yellow | LaGuardia | 3.34 | 7.78 | 9.50 | 69.96 |
| yellow | Newark | 0.17 | 0.76 | 17.30 | 131.57 |
| green | Sin aeropuerto | 96.66 | 93.65 | 2.08 | 20.12 |
| green | LaGuardia | 2.59 | 4.11 | 3.98 | 33.72 |
| green | JFK | 0.71 | 1.95 | 14.27 | 73.45 |

- **Interpretacion:** en yellow, los viajes de aeropuerto son el 8.2% de los
  viajes pero el 21.0% de los ingresos. Un viaje a JFK vale unas 4 veces un
  viaje urbano. En green, los viajes de aeropuerto son sobre todo llegadas a
  LaGuardia, que esta junto a su zona de operacion en Queens, porque green no
  puede recoger en aeropuertos (P6).

### 4. Variables de pago

#### P9 - `09_formas_de_pago.sql`

```sql
SELECT tipo, forma_pago,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_viajes,
       round(100 * sum(total_amount) / sum(sum(total_amount)) OVER (PARTITION BY tipo), 2) AS pct_ingresos,
       round(median(total_amount), 2) AS total_mediano,
       round(100 * avg((tip_amount > 0)::INT), 1) AS pct_con_propina
FROM viajes_validos
GROUP BY tipo, forma_pago
ORDER BY tipo, viajes DESC;
```

- **Resultado:**

| tipo | forma de pago | % viajes | % ingresos | total mediano | % con propina |
|---|---|---:|---:|---:|---:|
| yellow | Tarjeta | 65.64 | 65.15 | 22.35 | 91.2 |
| yellow | Flex Fare | 24.63 | 26.45 | 28.98 | 8.3 |
| yellow | Efectivo | 9.10 | 7.83 | 18.25 | 0.0 |
| yellow | Disputa / Sin cargo | 0.63 | 0.57 | | 0.0 |
| green | Tarjeta | 65.54 | 66.08 | 20.95 | 91.3 |
| green | Efectivo | 19.41 | 16.05 | 16.10 | 0.0 |
| green | Sin dato | 14.71 | 17.66 | 26.47 | 15.4 |
| green | Disputa / Sin cargo | 0.34 | 0.21 | | |

- **Interpretacion:**
  - Ambos tipos cobran dos tercios de sus viajes con tarjeta. Green usa el doble
    de efectivo que yellow (19.4% frente a 9.1%).
  - Flex Fare es la cuarta parte de yellow y tiene el monto mediano mas alto.
  - Las propinas en efectivo nunca se registran (0.0%), asi que cualquier
    analisis de propinas debe limitarse a pagos con tarjeta.
  - Green no tiene Flex Fare, pero su 14.7% "Sin dato" tiene un perfil parecido:
    un monto mayor y sin forma de pago. P11 muestra que tienen el mismo origen.

#### P10 - `10_flex_fare_mensual.sql`

```sql
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
```

- **Resultado:**

| mes | % Flex | Vendor 1 | Vendor 2 | Vendor 6 (viajes, % Flex) | Vendor 7 (viajes, % Flex) |
|---|---:|---:|---:|---|---|
| 2026-01 | 27.94 | 19.59 | 30.35 | 4,016 - 100% | 43,880 - 0% |
| 2026-02 | 28.58 | 19.86 | 30.99 | 5,599 - 100% | 39,680 - 0% |
| 2026-03 | 22.57 | 14.58 | 24.68 | 9,454 - 100% | 47,543 - 0% |
| 2026-04 | 19.89 | 13.26 | 21.65 | 9,862 - 100% | 48,643 - 0% |
| 2026-05 | 22.18 | 15.19 | 24.13 | 7,642 - 100% | 50,901 - 0% |
| 2026-06 | 24.97 | 18.71 | 26.39 | 8,675 - 100% | 48,625 - 0% |
| 2026-07 | 25.92 | 15.12 | 28.39 | 7,486 - 100% | 41,041 - 0% |
| 2026-08 | 26.19 | 15.00 | 28.85 | 6,650 - 100% | 40,061 - 0% |

- **Interpretacion:**
  - Flex Fare no es estable. Baja de 28.6% en febrero a 19.9% en abril y vuelve
    a 26.2% en agosto. Se mueve al reves que la demanda total (P1): pesa mas en
    los meses de menos viajes.
  - Los proveedores son muy distintos entre si. VendorID 6 (Myle) solo registra
    viajes Flex Fare y VendorID 7 (Helix) ninguno. VendorID 2 tiene entre 1.5
    y 1.9 veces mas Flex Fare que VendorID 1. El proveedor determina que campos
    llegan completos.

#### P11 - `11_flex_fare_origen.sql`

```sql
SELECT tipo, forma_pago,
       coalesce(request_source, 'NULL') AS request_source,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo, forma_pago), 2) AS pct_de_la_forma_pago
FROM viajes_validos
WHERE make_date(anio, mes, 1) >= DATE '2026-06-01'
GROUP BY tipo, forma_pago, request_source
HAVING count(*) >= 100
ORDER BY tipo, forma_pago, viajes DESC;
```

- **Objetivo:** cruzar la forma de pago con `request_source`, que solo existe
  desde junio de 2026.
- **Resultado (junio a agosto):**

| tipo | forma de pago | request_source | viajes | % de la forma de pago |
|---|---|---|---:|---:|
| yellow | Flex Fare | HV0003 | 2,092,429 | 79.25 |
| yellow | Flex Fare | A | 363,694 | 13.77 |
| yellow | Flex Fare | HV0005 | 162,333 | 6.15 |
| yellow | Flex Fare | EH0004 | 19,599 | 0.74 |
| yellow | Tarjeta, Efectivo, Disputa, Sin cargo | NULL | 7,649,223 | 100.00 |
| green | Sin dato | A | 17,562 | 94.51 |
| green | Sin dato | HV0005 | 1,020 | 5.49 |
| green | Tarjeta, Efectivo, Disputa, Sin cargo | NULL | 102,295 | 100.00 |

- **Interpretacion:**
  - `request_source` solo tiene valor en los viajes Flex Fare (y en los "Sin
    dato" de green). Todos los viajes cobrados con taximetro son `NULL`.
  - `HV0003` y `HV0005` son los numeros de licencia de Uber y Lyft como bases
    de alto volumen en la TLC (columna `hvfhs_license_num` del conjunto FHVHV).
    El 85% de los viajes Flex Fare de verano fueron solicitados desde esas
    aplicaciones. Flex Fare es, entonces, el segmento de taxis amarillos
    despachados por aplicacion con precio fijo de antemano, y por eso no trae
    los campos del taximetro (pasajeros, `RatecodeID`, `congestion_surcharge`).
  - Los codigos `A`, `CC` y los `EH` (licencias de e-hail) no estan en el
    diccionario publicado. `A` agrupa el 14% de Flex Fare y casi todo el "Sin
    dato" de green, asi que probablemente es otra aplicacion o despacho propio.

#### P12 - `12_propinas.sql`

```sql
WITH t AS (
    SELECT tipo, 100 * tip_amount / fare_amount AS pct_propina
    FROM viajes_validos
    WHERE payment_type = 1 AND fare_amount > 0
)
SELECT tipo,
       CASE WHEN pct_propina = 0 THEN '1. 0%'
            WHEN pct_propina < 10 THEN '2. (0, 10)'
            WHEN pct_propina < 15 THEN '3. [10, 15)'
            WHEN pct_propina < 20 THEN '4. [15, 20)'
            WHEN pct_propina < 25 THEN '5. [20, 25)'
            WHEN pct_propina < 30 THEN '6. [25, 30)'
            ELSE '7. 30% o mas' END AS rango_propina,
       count(*) AS viajes,
       round(100 * count(*) / sum(count(*)) OVER (PARTITION BY tipo), 2) AS pct_del_tipo
FROM t
GROUP BY tipo, rango_propina
ORDER BY tipo, rango_propina;
```

- **Objetivo:** ver la distribucion de la propina relativa. Solo se usan pagos
  con tarjeta, por lo visto en P9.
- **Resultado (% de viajes con tarjeta):**

| propina / tarifa | yellow | green |
|---|---:|---:|
| 0% | 8.79 | 8.66 |
| (0, 10) | 4.45 | 5.59 |
| [10, 15) | 6.85 | 7.26 |
| [15, 20) | 6.12 | 6.23 |
| [20, 25) | 15.88 | 30.93 |
| [25, 30) | 25.73 | 23.68 |
| 30% o mas | 32.18 | 17.66 |

- **Interpretacion:**
  - La distribucion no es suave: mas del 70% de los viajes cae en 20% o mas, lo
    que apunta a las propinas sugeridas en las pantallas de pago.
  - Yellow deja propinas mas altas que green: en yellow, el 32% de los viajes
    supera el 30% de la tarifa, mientras que green se concentra en el rango de
    20% a 25%.
  - El porcentaje se calcula sobre `fare_amount`. Si las sugerencias se aplican
    sobre la tarifa mas los recargos, que en yellow son mayores, la propina sobre
    la tarifa sale mas alta. Esto puede explicar parte de la diferencia.

### 5. Valores atipicos e inconsistencias

#### P13 - `13_consistencia_montos.sql`

```sql
WITH d AS (
    SELECT tipo, VendorID, coalesce(payment_type = 0, false) AS es_flex, extra,
           fare_amount + extra + mta_tax + tip_amount + tolls_amount + improvement_surcharge
               + coalesce(Airport_fee, 0) + coalesce(ehail_fee, 0) AS base,
           coalesce(congestion_surcharge, 0) + coalesce(cbd_congestion_fee, 0) AS recargos_congestion,
           total_amount
    FROM viajes_validos
)
SELECT tipo, VendorID, es_flex,
       count(*) AS viajes,
       round(100 * avg((abs(total_amount - base - recargos_congestion) <= 0.01)::INT), 1) AS pct_cuadra_con_recargos,
       round(100 * avg((abs(total_amount - base) <= 0.01)::INT), 1) AS pct_cuadra_sin_recargos,
       round(avg(extra), 2) AS extra_promedio,
       round(avg(recargos_congestion), 2) AS recargos_promedio
FROM d
GROUP BY ALL
HAVING count(*) >= 100
ORDER BY tipo, VendorID, es_flex;
```

- **Objetivo:** comprobar si `total_amount` es la suma de las columnas de cargos.
  Se prueban dos formulas: con los recargos de congestion (`congestion_surcharge`
  + `cbd_congestion_fee`) y sin ellos.
- **Resultado:**

| tipo | VendorID | Flex | viajes | % cuadra con recargos | % cuadra sin recargos | `extra` prom. |
|---|---:|---|---:|---:|---:|---:|
| yellow | 1 | no | 4,499,053 | 16.3 | **94.7** | 3.41 |
| yellow | 1 | si | 877,431 | 1.4 | 1.4 | 0.16 |
| yellow | 2 | no | 16,699,134 | **99.9** | 6.8 | 1.04 |
| yellow | 2 | si | 6,108,172 | 12.0 | 11.8 | 0.00 |
| yellow | 6 | si | 59,384 | 0.0 | 0.0 | 0.00 |
| yellow | 7 | no | 360,374 | 57.1 | 2.6 | 0.00 |
| green | 1 | no | 27,000 | 3.2 | 4.4 | 1.88 |
| green | 2 | no | 262,319 | **98.4** | 67.1 | 0.84 |
| green | 6 | no | 34,842 | 0.0 | 0.0 | 0.00 |

- **Interpretacion:**
  - El significado de `extra` depende del proveedor. VendorID 2 registra los
    recargos de congestion en sus columnas y `extra` solo trae los cargos
    nocturnos o de hora pico: el total cuadra con la formula completa (99.9%).
    VendorID 1 incluye ademas esos recargos dentro de `extra` (prom. 3.41, con
    valores tipicos de 2.50 y 3.25 = 2.50 + 0.75). Si se suman todas las
    columnas, se cuentan dos veces y el total solo cuadra si se omiten (94.7%).
  - En Flex Fare los componentes estan incompletos. Por ejemplo,
    `congestion_surcharge` es `NULL` pero el total incluye esos 2.50 USD. Lo
    mismo pasa con Myle (VendorID 6).
  - **Decision:** `total_amount` es la unica columna monetaria confiable entre
    proveedores. No se deben sumar ni comparar `extra` o los recargos por
    separado sin distinguir el `VendorID`.

#### P14 - `14_registros_excluidos.sql`

```sql
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
```

- **Fuente:** la vista `viajes`, sin filtrar.
- **Resultado:**

| tipo | registros | fecha | duracion | distancia | monto negativo | excluidos | % |
|---|---:|---:|---:|---:|---:|---:|---:|
| green | 337,114 | 98 | 238 | 12,281 | 1,025 | 12,953 | 3.84 |
| yellow | 29,703,355 | 146 | 4,826 | 952,935 | 161,970 | 1,099,807 | 3.70 |

- **Interpretacion:** se excluye menos del 4% de cada tipo, y la regla que mas
  pesa es la distancia cero. Una fila puede incumplir varias reglas, por eso
  las columnas no suman el total. Antes del ajuste por Helix (P16), la regla de
  duracion excluia 371,946 viajes yellow y el total excluido era 4.92%.

#### P15 - `15_atipicos_iqr.sql`

La consulta (en el archivo) calcula Q1 y Q3 de cada metrica por tipo, el limite
superior de Tukey `Q3 + 1.5 * IQR` y cuantos viajes lo superan. Tambien cuenta
los viajes con velocidad mayor a 80 mph, que es fisicamente implausible para un
taxi en la ciudad.

- **Resultado:**

| metrica | tipo | Q1 | Q3 | limite | atipicos | % | maximo |
|---|---|---:|---:|---:|---:|---:|---:|
| distancia (mi) | green | 1.33 | 3.78 | 7.46 | 33,000 | 10.18 | 134.49 |
| distancia (mi) | yellow | 1.10 | 3.93 | 8.18 | 3,143,401 | 10.99 | 199.30 |
| duracion (min) | green | 8.68 | 20.73 | 38.81 | 23,028 | 7.10 | 1,439.80 |
| duracion (min) | yellow | 8.62 | 22.27 | 42.74 | 1,534,511 | 5.36 | 1,439.93 |
| total (USD) | green | 15.12 | 29.70 | 51.57 | 21,581 | 6.66 | 1,678.20 |
| total (USD) | yellow | 17.45 | 34.43 | 59.90 | 2,444,058 | 8.54 | 7,053.50 |
| velocidad (mph) | green | 7.93 | 13.12 | 20.89 | 22,001 | 6.79 | 82,272.00 |
| velocidad (mph) | yellow | 6.83 | 12.93 | 22.08 | 1,873,306 | 6.55 | 68,940.00 |

  Viajes de mas de 80 mph: 7,294 en yellow y 1,087 en green.

- **Interpretacion:**
  - La regla de Tukey marca entre 5% y 11% de los viajes como atipicos. Esto no
    son errores: es la cola natural de una distribucion asimetrica. Por ejemplo,
    el limite de distancia de yellow (8.18 mi) deja fuera a casi todos los
    viajes a JFK (mediana de 16.9 mi, P8). Por eso **no se usa IQR para
    eliminar registros**.
  - Los errores reales son los valores fisicamente imposibles: 8,381 viajes de
    mas de 80 mph, que vienen de distancias infladas o duraciones de segundos.
  - **Decision:** el analisis usa medianas, que no se ven afectadas por esos
    valores. Al materializar la tabla del Ejercicio 6 se recomienda agregar la
    regla `velocidad <= 80 mph`.
  - **Rendimiento:** la primera version de esta consulta pasaba las 4 metricas
    a formato largo (113 millones de filas) y las unia con los cuartiles por
    `(tipo, metrica)`. Tardaba 234 s. La version final calcula los cuartiles en
    una tabla de 2 filas (una por tipo) y la une por `tipo`; da el mismo
    resultado en unos 17 s.

#### P16 - `16_duracion_cero_vendor.sql`

```sql
SELECT tipo, VendorID,
       count(*) AS registros,
       count(*) FILTER (WHERE dropoff = pickup) AS duracion_cero,
       round(100 * count(*) FILTER (WHERE dropoff = pickup) / count(*), 2) AS pct_duracion_cero,
       round(100 * count(*) FILTER (WHERE dropoff = pickup)
             / sum(count(*) FILTER (WHERE dropoff = pickup)) OVER (PARTITION BY tipo), 2) AS pct_del_total_cero,
       round(median(trip_distance) FILTER (WHERE dropoff = pickup), 2) AS distancia_mediana_cero,
       round(median(fare_amount) FILTER (WHERE dropoff = pickup), 2) AS tarifa_mediana_cero
FROM viajes
GROUP BY tipo, VendorID
ORDER BY tipo, VendorID;
```

- **Fuente:** la vista `viajes`, sin filtrar.
- **Resultado:**

| tipo | VendorID | registros | duracion cero | % del proveedor | % del total cero | distancia med. | tarifa med. |
|---|---:|---:|---:|---:|---:|---:|---:|
| yellow | 1 | 5,467,071 | 4,297 | 0.08 | 1.16 | 0.00 | 10.12 |
| yellow | 2 | 23,809,774 | 256 | 0.00 | 0.07 | 0.00 | 18.98 |
| yellow | 7 | 367,120 | 367,120 | **100.00** | **98.77** | 1.51 | 12.10 |
| green | 1 | 28,696 | 86 | 0.30 | 37.55 | 0.00 | 7.90 |
| green | 2 | 273,571 | 143 | 0.05 | 62.45 | 0.00 | 10.00 |

- **Interpretacion:** el 98.8% de los viajes yellow con duracion cero son de
  VendorID 7 (Helix), y **todos** los viajes de Helix tienen
  `dropoff = pickup`. Ademas tienen distancia (1.51 mi) y tarifa (12.10 USD)
  normales, mientras que los de duracion cero de los demas proveedores tienen
  distancia 0, como un viaje cancelado.
- **Decision:** Helix no registra la hora de bajada. Sus viajes son reales, asi
  que en `00_vistas.sql` su duracion pasa a `NULL` y dejan de excluirse. Con
  esto se recuperan 367,120 viajes (1.24% de yellow) para los analisis de
  volumen, pago y zonas. Las metricas de duracion y velocidad los ignoran.
  Esto corrige la suposicion del Ejercicio 3 de que la duracion cero eran
  cancelaciones.

#### P17 - `17_pasajeros_por_vendor.sql`

```sql
SELECT VendorID, passenger_count,
       count(*) AS viajes,
       round(median(trip_distance), 2) AS distancia_mediana_mi,
       round(median(total_amount), 2) AS total_mediano
FROM viajes_validos
WHERE tipo = 'green' AND passenger_count BETWEEN 3 AND 6
GROUP BY VendorID, passenger_count
ORDER BY VendorID, passenger_count;
```

- **Resultado:**

| VendorID | pasajeros | viajes | distancia med. (mi) | total med. (USD) |
|---:|---:|---:|---:|---:|
| 1 | 3 | 607 | 2.10 | 20.90 |
| 1 | 4 | 149 | 2.50 | 23.05 |
| 1 | 5 | 19 | 2.10 | 19.60 |
| 1 | 6 | 8 | 2.20 | 20.90 |
| 2 | 3 | 2,490 | 2.09 | 21.30 |
| 2 | 4 | 2,104 | 2.98 | 35.00 |
| 2 | 5 | 6,148 | 1.85 | 19.20 |
| 2 | 6 | 4,235 | 1.68 | 18.10 |

- **Interpretacion:** la anomalia viene solo de VendorID 2. En sus datos, los
  viajes de 5 y 6 pasajeros son mas frecuentes, mas cortos y mas baratos que
  los de 3 y 4. Eso no corresponde a viajes de grupo, que suelen ir en
  vehiculos mas grandes y no tienen por que ser mas cortos. Lo mas probable es
  un problema de captura del dato (un valor por defecto o un mapeo erroneo).
- **Decision:** `passenger_count` de green VendorID 2 no se usa para analizar
  ocupacion de mas de 2 pasajeros.

---

## 4.5 Hallazgos relevantes

1. **Una cuarta parte de los taxis amarillos se piden por aplicacion.** Los
   viajes Flex Fare (`payment_type = 0`) son el 24.6% de yellow y el 26.5% de
   sus ingresos. Entre junio y agosto, el 85% vino de Uber (`HV0003`) y Lyft
   (`HV0005`) (P9 a P11). Son viajes con precio fijo, sin datos de taximetro,
   y explican casi todos los nulos de `passenger_count` y `RatecodeID` que
   detecto el Ejercicio 3. Cualquier indicador de pasajeros, tarifa o recargos
   debe separar este segmento.
2. **Los campos dependen del proveedor del taximetro, no solo del viaje.**
   VendorID 1 incluye los recargos de congestion en `extra` y VendorID 2 no
   (P13). Helix (VendorID 7) no registra la hora de bajada (P16). Myle
   (VendorID 6) solo reporta Flex Fare (P10). VendorID 2 de green tiene
   conteos de pasajeros inverosimiles (P17). Comparar columnas entre
   proveedores sin tener esto en cuenta produce conclusiones falsas. Por
   ejemplo, la regla de duracion del Ej. 3 descartaba 367 mil viajes reales.
3. **Yellow y green son mercados distintos, no el mismo servicio en dos
   colores.** El 83% de yellow sale del centro de Manhattan y el 8% de sus
   viajes (21% de ingresos) toca un aeropuerto. Green sale en un 93% de la
   Boro Zone, y el 40% solo de East Harlem (P6 a P8). Green es un servicio de
   traslado laboral (picos de 7 a 9 h y de 16 a 18 h), mientras que yellow
   tambien cubre la vida nocturna de fin de semana (P2). Green paga mas en
   efectivo (19% frente a 9%) y deja propinas mas bajas (P9 y P12).
4. **La congestion reduce la distancia del viaje, no alarga su duracion.** En
   dias laborales, la velocidad mediana de yellow cae de 16.8 mph a las 4 h a
   7.3 mph a las 11 h. La duracion mediana se mantiene entre 13 y 16 minutos, y
   lo que se acorta es la distancia, de 4.3 a 1.6 mi (P4).
5. **El verano reduce la demanda de yellow.** Los viajes diarios de yellow caen
   19% de mayo a agosto, mientras que green vuelve a su nivel de enero. El
   monto promedio de green crece 9% en el periodo (P1).

## Resumen de decisiones

1. Usar vistas (`viajes`, `viajes_validos`, `zonas`) definidas una sola vez,
   con las reglas de calidad como columnas booleanas.
2. Tratar la duracion de VendorID 7 (Helix) como dato faltante en lugar de
   excluir sus viajes. Esto ajusta la regla de duracion del Ejercicio 3.
3. Usar `total_amount` como unica medida monetaria comparable entre proveedores.
4. Analizar propinas solo en pagos con tarjeta.
5. Separar Flex Fare (yellow) y "Sin dato" (green) en los analisis de
   pasajeros, tarifa y recargos.
6. No usar IQR para eliminar registros. Usar medianas y, al materializar,
   agregar la regla de velocidad maxima de 80 mph.
7. No usar `passenger_count` de green VendorID 2 para ocupacion de mas de 2
   pasajeros.

Ninguna decision modifica los archivos de `data/raw/`. Todas viven en las
vistas o en las consultas.
