# Ejercicio 5 - Incorporacion de los datos de 2024

En este ejercicio se amplia el sistema para trabajar con los taxis yellow y
green de 2024 ademas de los de 2026. Los datos de 2024 se obtienen de la fuente
original de la TLC con el mismo script de descarga, sin pasos manuales.

Las consultas de validacion estan en `sql/ejercicio5/` y el notebook
`notebooks/03_incorporacion_2024.ipynb` las ejecuta junto con la prueba de
compatibilidad de las consultas anteriores. Los resultados corresponden a la
ejecucion del 7 de octubre de 2026.

## Como ejecutar

```bash
# 5.4 Descargar 2024 y 2026 (los archivos existentes se omiten)
docker compose exec lab python scripts/download_data.py

# 5.5 a 5.8 Validar la incorporacion (tarda unos 13 minutos)
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/03_incorporacion_2024.ipynb
```

---

## 5.1 Cambios al sistema de descarga

El script fijaba el anio en una constante (`ANIO = 2026`) que se usaba en los
nombres de archivo, las rutas y el manifiesto. Los cambios en
`scripts/download_data.py` son:

| Cambio | Motivo |
|---|---|
| `ANIO = 2026` se reemplazo por `ANIOS = (2024, 2026)` | los anios del laboratorio quedan en un solo lugar; en el Ejercicio 8 basta con agregar 2025 |
| Nuevo argumento `--anio`, que acepta uno o varios anios | descargar un anio puntual sin editar el script |
| Validacion del rango de anios (2009, primer anio de la TLC, hasta el anio actual) | un anio imposible se rechaza antes de hacer peticiones |
| `construir_nombre`, `construir_url`, `ruta_destino` y `descargar` reciben el anio como parametro | la misma logica sirve para cualquier anio |
| Un manifiesto por anio (`data/raw/manifest_<anio>.csv`) | descargar un anio no reescribe el registro de otro |
| El resumen muestra las filas por anio y la lista de manifiestos | evidencia de que se proceso cada anio |

La logica de cada archivo no cambio: consultar el `Content-Length`, omitir el
archivo si el local pesa lo mismo, descargar sobre un `.part`, verificar los
bytes y validar el footer Parquet. Por eso 5.2 y 5.3 se cumplen por
construccion: un archivo de 2026 completo nunca se vuelve a descargar ni se
modifica.

## 5.2 y 5.3 Conservacion de 2026 y no repeticion de descargas

Antes de ejecutar el script modificado se guardo el tamanio y la fecha de
modificacion de los 16 archivos de 2026 y el hash MD5 de `manifest_2026.csv`:

```bash
docker compose exec lab sh -c 'find data/raw -path "*2026*" -name "*.parquet" \
    -exec stat -c "%n %s %Y" {} \; | sort; md5sum data/raw/manifest_2026.csv'
```

Despues de las dos ejecuciones del punto 5.4, el mismo comando dio una salida
identica (`diff` sin diferencias). Los archivos de 2026 no se descargaron, no se
reescribieron y el manifiesto de 2026 no cambio.

## 5.4 Ejecucion del proceso de descarga

**Primera ejecucion**, con 2026 ya descargado:

```text
=== YELLOW 2024 ===
  2024-01  listo (47.6 MiB) -> data/raw/yellow/2024/yellow_tripdata_2024-01.parquet
  ...
  2024-12  listo (58.7 MiB) -> data/raw/yellow/2024/yellow_tripdata_2024-12.parquet
=== GREEN 2024 ===
  ...
=== YELLOW 2026 ===
  2026-01  ya existe, se omite
  ...
  2026-09  aun no publicado por la TLC
...
RESUMEN
  descargados   : 24
  ya existian   : 16
  no publicados : 8
  fallidos      : 0
  filas 2024    : 41,829,938
  filas 2026    : 30,040,469
  filas totales : 71,870,407
  manifiestos   : data/raw/manifest_2024.csv, data/raw/manifest_2026.csv
```

**Segunda ejecucion:** `descargados: 0`, `ya existian: 40`, `fallidos: 0`. El
script es idempotente.

2024 ocupa unos 670 MB: 12 archivos yellow de 48 a 61 MiB y 12 green de 1.2 a
1.4 MiB.

---

## 5.5 Verificacion de los nuevos archivos

### 01 - `01_archivos_por_anio.sql`

```sql
SELECT regexp_extract(file, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(file, '/(\d{4})/', 1)::INT AS anio,
       count(*) AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet', 1)) AS ultimo_mes
FROM glob('data/raw/*/*/*.parquet')
GROUP BY ALL
ORDER BY anio, tipo;
```

- **Objetivo:** confirmar que estan los 12 meses de 2024 por tipo, sin perder los de 2026.
- **Fuente:** listado de `data/raw/*/*/*.parquet` (solo nombres).
- **Resultado:**

| tipo | anio | archivos | primer mes | ultimo mes |
|---|---:|---:|---|---|
| green | 2024 | 12 | 2024-01 | 2024-12 |
| yellow | 2024 | 12 | 2024-01 | 2024-12 |
| green | 2026 | 8 | 2026-01 | 2026-08 |
| yellow | 2026 | 8 | 2026-01 | 2026-08 |

- **Decision:** 2024 esta completo. A diferencia de 2026, la TLC ya publico
  los 12 meses.

### 02 - `02_manifiesto_vs_metadata.sql`

```sql
WITH manifiesto AS (
    SELECT archivo, tipo, filas
    FROM read_csv('data/raw/manifest_*.csv', header = true)
), metadata AS (
    SELECT file_name AS archivo, num_rows AS filas
    FROM parquet_file_metadata('data/raw/*/*/*.parquet')
)
SELECT coalesce(m.tipo, regexp_extract(p.archivo, 'raw/(\w+)/', 1)) AS tipo,
       regexp_extract(coalesce(m.archivo, p.archivo), '/(\d{4})/', 1)::INT AS anio,
       count(m.archivo) AS archivos_manifiesto,
       count(p.archivo) AS archivos_en_disco,
       sum(m.filas) AS filas_manifiesto,
       sum(p.filas) AS filas_metadata,
       count(*) FILTER (WHERE m.archivo IS NULL OR p.archivo IS NULL OR m.filas <> p.filas) AS diferencias
FROM manifiesto m
FULL OUTER JOIN metadata p USING (archivo)
GROUP BY ALL
ORDER BY anio, tipo;
```

- **Objetivo:** contrastar dos fuentes independientes: lo que el script dice
  que descargo (los manifiestos, leidos con un glob sobre los CSV) y lo que
  realmente hay en disco (el footer de cada Parquet). El `FULL OUTER JOIN`
  detecta archivos que solo esten en uno de los dos lados.
- **Fuente:** `data/raw/manifest_*.csv` y los 40 Parquet.
- **Resultado:**

| tipo | anio | archivos manifiesto | archivos en disco | filas manifiesto | filas metadata | diferencias |
|---|---:|---:|---:|---:|---:|---:|
| green | 2024 | 12 | 12 | 660,218 | 660,218 | 0 |
| yellow | 2024 | 12 | 12 | 41,169,720 | 41,169,720 | 0 |
| green | 2026 | 8 | 8 | 337,114 | 337,114 | 0 |
| yellow | 2026 | 8 | 8 | 29,703,355 | 29,703,355 | 0 |

- **Decision:** no hay archivos huerfanos ni diferencias de filas. La
  descarga de 2024 esta completa e integra.

### 03 - `03_esquema_por_anio.sql`

La consulta (en el archivo) lee el esquema de los 40 archivos con
`parquet_schema` y muestra las columnas que cambian de tipo entre anios, que
faltan en algun anio o que faltan en algunos meses.

- **Objetivo:** saber si el esquema de 2024 es compatible con el de 2026 antes
  de consultarlos juntos.
- **Resultado:**

| tipo | columna | detalle |
|---|---|---|
| green / yellow | `cbd_congestion_fee` | solo en 2026 (8 de 8 archivos), DOUBLE |
| green / yellow | `request_source` | solo en 2026 (3 de 8 archivos), VARCHAR |

- **Decision:**
  - Ninguna columna cambia de tipo entre 2024 y 2026, y los nombres coinciden,
    incluida la mayuscula de `Airport_fee`.
  - Las dos diferencias son columnas que no existian en 2024.
    `cbd_congestion_fee` corresponde al cargo por congestion de Manhattan, que
    empezo a cobrarse en enero de 2025. `request_source` se agrego en junio de
    2026. Con `union_by_name = true` ambas quedan en `NULL` para 2024, que es lo
    correcto: el cargo no existia, no es un dato faltante.

---

## 5.6 Consulta conjunta de 2024 y 2026

### 04 - `04_conteo_conjunto.sql`

```sql
SELECT regexp_extract(filename, 'raw/(\w+)/', 1) AS tipo,
       regexp_extract(filename, '/(\d{4})/', 1)::INT AS anio,
       count(DISTINCT filename) AS archivos,
       count(*) AS registros
FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
GROUP BY ALL
ORDER BY anio, tipo;
```

- **Objetivo:** demostrar que un solo `read_parquet` con un glob lee los 40
  archivos de los dos anios y los dos tipos como una sola fuente.
- **Resultado:** 660,218 + 41,169,720 (2024) y 337,114 + 29,703,355 (2026), en
  total 71,870,407 registros, igual que el manifiesto y la metadata. Tarda menos
  de un segundo.

### 05 - `05_calidad_por_anio.sql`

```sql
SELECT tipo, left(mes_archivo, 4)::INT AS anio,
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
```

- **Objetivo:** aplicar a 2024 las reglas de calidad del Ejercicio 4, usando las
  mismas vistas sin modificarlas, y ver si los problemas son los mismos.
- **Fuente:** la vista `viajes` (`sql/ejercicio4/00_vistas.sql`), que ahora lee
  los dos anios.
- **Resultado:**

| tipo | anio | registros | fecha | duracion | distancia | monto neg. | % excluidos | % null pasajeros | % payment 0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| green | 2024 | 660,218 | 164 | 662 | 34,807 | 2,185 | 5.51 | 3.68 | 0.00 |
| green | 2026 | 337,114 | 98 | 238 | 12,281 | 1,025 | 3.84 | 14.47 | 0.00 |
| yellow | 2024 | 41,169,720 | 420 | 13,510 | 777,447 | 733,885 | 3.54 | 9.94 | 9.94 |
| yellow | 2026 | 29,703,355 | 146 | 4,826 | 952,935 | 161,970 | 3.70 | 25.98 | 25.98 |

- **Decision:**
  - Las reglas funcionan sin cambios en 2024 y excluyen una proporcion
    parecida (3.5% a 5.5%).
  - En yellow 2024, el porcentaje de `passenger_count` nulo y el de
    `payment_type = 0` vuelven a coincidir (9.94%), como en 2026, lo que indica
    que la relacion que encontro el Ejercicio 3 tambien vale en 2024. Flex Fare
    ya existia en 2024, aunque con menos peso.
  - Los montos negativos de yellow eran 3.3 veces mas frecuentes en 2024
    (1.78% frente a 0.55%). La regla `ok_monto` los cubre.

### 06 - `06_comparacion_2024_2026.sql`

```sql
WITH meses_comunes AS (
    SELECT mes FROM viajes_validos
    GROUP BY mes
    HAVING count(DISTINCT anio) = (SELECT count(DISTINCT anio) FROM viajes_validos)
)
SELECT tipo, anio,
       count(DISTINCT mes) AS meses,
       round(count(*) / count(DISTINCT pickup::DATE), 0) AS viajes_por_dia,
       round(avg(total_amount), 2) AS total_promedio,
       round(median(trip_distance), 2) AS distancia_mediana_mi,
       round(median(duracion_min), 1) AS duracion_mediana_min,
       round(100 * avg(coalesce(payment_type = 1, false)::INT), 2) AS pct_tarjeta,
       round(100 * avg(coalesce(payment_type = 2, false)::INT), 2) AS pct_efectivo,
       round(100 * avg(coalesce(payment_type = 0, false)::INT), 2) AS pct_flex,
       round(100 * avg((payment_type IS NULL)::INT), 2) AS pct_sin_dato
FROM viajes_validos
WHERE mes IN (SELECT mes FROM meses_comunes)
GROUP BY tipo, anio
ORDER BY tipo, anio;
```

- **Objetivo:** hacer una primera comparacion entre anios, limitada a los meses
  que ambos tienen. Los meses comunes se calculan a partir de los datos (no se
  fija "enero a agosto"), asi que la consulta sigue siendo valida cuando se
  publiquen mas meses de 2026 o se agregue 2025.
- **Resultado (enero a agosto):**

| tipo | anio | viajes/dia | total prom. | dist. med. | dur. med. | tarjeta | efectivo | Flex | sin dato |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| green | 2024 | 1,716 | 23.86 | 1.96 | 11.9 | 67.74% | 27.79% | 0.00% | 4.02% |
| green | 2026 | 1,334 | 25.54 | 2.15 | 13.4 | 65.54% | 19.41% | 0.00% | 14.71% |
| yellow | 2024 | 104,571 | 28.33 | 1.80 | 12.7 | 75.92% | 13.79% | 8.99% | 0.00% |
| yellow | 2026 | 117,710 | 30.20 | 1.92 | 14.1 | 65.64% | 9.10% | 24.63% | 0.00% |

- **Interpretacion:** la consulta conjunta funciona y ya muestra tendencias que
  el Ejercicio 8 analizara con 2025:
  - yellow crecio 12.6% en viajes por dia, mientras que green cayo 22.3%;
  - Flex Fare paso de 9.0% a 24.6% de yellow, a costa del pago con tarjeta y
    en efectivo;
  - el efectivo cae en ambos tipos;
  - el monto promedio subio cerca de 7% en ambos tipos;
  - los viajes duran mas (unos 1.4 min en la mediana) y son algo mas largos.

### Consulta 01 del Ejercicio 4 sin modificar

`sql/ejercicio4/01_viajes_por_mes.sql` ya agrupaba por `anio` y `mes`, asi que
sin cambiar una linea devuelve las dos series (40 filas). El notebook las
grafica: la caida de julio y agosto que el Ejercicio 4 vio en 2026 tambien
ocurre en 2024, lo que confirma que es estacional. En septiembre de 2024 la
demanda de yellow se recupera.

---

## 5.7 Necesitan modificarse las consultas anteriores?

El notebook ejecuta automaticamente las 34 consultas de los Ejercicios 3 y 4
sobre el conjunto ampliado y registra si terminan, cuanto tardan (con
`time.perf_counter()`, porque el reloj del contenedor da saltos al
sincronizarse con WSL y `time.time()` llego a medir tiempos negativos) y si su
resultado distingue el anio.

### Ejercicio 3

Las 17 consultas fijan la ruta en `/2026/` (por ejemplo,
`read_parquet('data/raw/yellow/2026/*.parquet')`).

| Prueba | Resultado |
|---|---|
| Tal cual | 17 de 17 terminan, pero **solo leen 2026**: ignoran 2024 sin dar error |
| Reemplazando `/2026/` por `/*/` | 16 de 17 terminan sobre los 40 archivos |
| `15_duplicados.sql` con `/*/` | **falla**: `Out of Memory Error ... (3.7 GiB/3.7 GiB used)` |

Conclusiones:

- **Si necesitan modificarse** para cubrir 2024, porque el anio esta en la ruta.
  El cambio es mecanico (cambiar `/2026/` por `/*/`), y que 16 de 17 sigan
  funcionando muestra que la logica no depende del anio. Es un error silencioso:
  la consulta "funciona", pero responde sobre menos datos de los esperados.
- **La consulta 15 no escala.** `SELECT DISTINCT *` construye una tabla con las
  20 columnas de cada fila distinta, lo que con 71 millones de filas no cabe en
  los 5.6 GB de memoria del contenedor ni en el limite de 4 GB de temporales.
  Se reemplazo por `07_duplicados_escalable.sql`, que compara un hash de 64 bits
  por fila. Da el mismo resultado que la original para 2026 (7 duplicados en
  yellow), y sobre los dos anios tarda unos 20 s, mientras que la original
  tarda de 2 a 4 minutos solo con 2026. En 2024 hay 4 duplicados en yellow y
  ninguno en green.
- **Dos consultas cambian de significado.** La 11 cuenta `year(pickup) <> 2026`
  como "fuera de rango", lo que con 2024 marcaria todos sus viajes; la
  comparacion correcta es con el mes del archivo, que es la que ya usa la
  columna `fuera_del_mes`. Las consultas que agrupan solo por `tipo` mezclan
  los anios.
- **Decision:** las consultas del Ejercicio 3 se conservan como estan. Son la
  exploracion documentada de 2026, y sus resultados en `docs/ejercicio3.md`
  dependen de que lean solo ese anio. El analisis multianual se hace con las
  vistas del Ejercicio 4, que ya resuelven estos puntos.

### Ejercicio 4

Las vistas de `00_vistas.sql` leen `data/raw/<tipo>/*/*.parquet`, asi que las
17 consultas se ejecutan **sin ningun cambio**:

| Prueba | Resultado |
|---|---|
| Terminan sin error | 17 de 17 |
| Distinguen el anio en el resultado | 01 y 10 (agrupan por `anio` y `mes`) |
| Fijan un periodo valido para cualquier anio | 11 (`>= 2026-06-01`, porque `request_source` solo existe desde entonces) |
| Tiempo | entre 2.7 y 4 veces mas que con solo 2026 (por ejemplo, la 03 pasa de 12 a 44 s), algo mas que la proporcion de filas (71.9 M frente a 30 M, 2.4 veces). La 15 (IQR) pasa de 17 a 112 s, porque los cuartiles exactos sobre 70 M de valores ya no caben en memoria y DuckDB usa temporales. Son mediciones de una sola ejecucion; la comparacion rigurosa de tiempos es el Ejercicio 6 |

Conclusiones:

- **No necesitan modificarse para funcionar.** Las reglas de calidad no
  dependen del anio: `ok_fecha` compara con el mes del archivo, no con 2026.
- **Si necesitan un ajuste para interpretarse por anio.** Las otras 14 consultas
  agrupan por `tipo` y devuelven agregados de 2024 y 2026 mezclados (por
  ejemplo, el % de Flex Fare promedio de ambos anios). El ajuste es agregar
  `anio` al `SELECT`, al `GROUP BY` y a las `PARTITION BY` de las ventanas. Se
  hara en el Ejercicio 8, al actualizar los indicadores para los tres anios.
  Hacerlo ahora cambiaria los resultados documentados del Ejercicio 4.
- **La reproducibilidad del Ejercicio 4 no se pierde.** Sus resultados
  documentados y las salidas guardadas del notebook `02` corresponden a 2026. Si
  se vuelve a ejecutar con 2024 descargado, las consultas que no agrupan por
  anio daran agregados de ambos anios.

### Incidente: temporales de DuckDB

La primera vez que se ejecuto esta prueba, `15_duplicados.sql` con el glob
generalizado escribio mas de 8 GB de temporales en `.tmp/`, dentro del disco
virtual de Docker. El disco del anfitrion se lleno y Docker Desktop se detuvo.
Para recuperarlo hubo que eliminar el contenedor y compactar
`docker_data.vhdx` con `diskpart`, porque el disco virtual crece pero no se
reduce solo. Para evitar que se repita, `sql/ejercicio4/00_vistas.sql` ahora
empieza con:

```sql
SET temp_directory = 'data/processed/duckdb_tmp';
SET max_temp_directory_size = '4GB';
```

Con esto, los temporales quedan visibles desde el anfitrion, ignorados por Git
y limitados. Una consulta que necesita mas falla con un error claro en lugar
de llenar el disco, que es justo lo que ocurrio en la segunda ejecucion.

---

## 5.8 Consultas utilizadas para validar la incorporacion de 2024

| Consulta | Valida | Punto |
|---|---|---|
| `01_archivos_por_anio.sql` | estan los 12 meses de 2024 y se conservan los 8 de 2026 | 5.2, 5.5 |
| `02_manifiesto_vs_metadata.sql` | lo descargado (manifiestos) coincide con lo que hay en disco (metadata) | 5.5 |
| `03_esquema_por_anio.sql` | el esquema de 2024 es compatible con el de 2026 | 5.5 |
| `04_conteo_conjunto.sql` | un solo glob lee ambos anios | 5.6 |
| `05_calidad_por_anio.sql` | las reglas de calidad funcionan en 2024 | 5.6 |
| `06_comparacion_2024_2026.sql` | se pueden comparar los anios en una sola consulta | 5.6 |
| `07_duplicados_escalable.sql` | reemplazo escalable de la consulta 15 del Ej. 3 | 5.7 |
| prueba automatica del notebook | las 34 consultas anteriores sobre el conjunto ampliado | 5.7 |

Cada una esta documentada arriba con su SQL, objetivo, fuente, resultado y
decision.

## 5.9 Caracteristicas del diseno que permiten incorporar archivos sin rehacer el flujo

1. **Estructura de directorios por tipo y anio.** Los archivos viven en
   `data/raw/<tipo>/<anio>/` con el nombre original de la TLC. Un anio nuevo es
   una carpeta nueva; nada de lo existente se mueve ni se renombra.
2. **Descarga parametrizada e idempotente.** Los anios estan en una constante
   (`ANIOS`) y en un argumento (`--anio`). El script compara cada archivo con
   el servidor y solo descarga lo que falta, de modo que volver a ejecutarlo es
   seguro. Cada anio tiene su manifiesto.
3. **Globs en lugar de listas de archivos.** `read_parquet('data/raw/yellow/*/*.parquet')`
   descubre los archivos al momento de consultar. No hay un catalogo que
   actualizar ni una carga que repetir: el archivo nuevo entra en la siguiente
   consulta.
4. **Tolerancia a cambios de esquema.** `union_by_name = true` y
   `UNION ALL BY NAME` alinean las columnas por nombre y rellenan con `NULL` las
   que no existen en un anio (`cbd_congestion_fee` en 2024).
5. **Logica definida una vez, en vistas.** La union de tipos, las columnas
   derivadas y las reglas de calidad estan en `00_vistas.sql`. Las consultas
   leen `viajes_validos` y no saben de rutas ni anios.
6. **Nada fijado a un anio.** El anio y el mes salen de los datos (`year(pickup)`)
   o del nombre del archivo (`mes_archivo`). Las reglas comparan con el mes del
   archivo, y la comparacion entre anios calcula los meses comunes en lugar de
   suponerlos.
7. **Consultar Parquet directamente.** Como no hay una tabla materializada,
   incorporar datos no exige recargar nada. El costo es que cada consulta
   procesa todo el volumen, lo que se evalua en el Ejercicio 6.

El contraejemplo son las consultas del Ejercicio 3, que fijan `/2026/` en la
ruta. Siguen funcionando, pero ignoran 2024 sin avisar. Esa diferencia es la
razon para centralizar las rutas en vistas.
