# Lab 8 - DuckDB

Repositorio base del laboratorio 8 del curso **CC3084 - Data Science**
(Universidad del Valle de Guatemala, Ciclo 2, 2026).

Este es el repositorio **proporcionado por el docente**. Contiene la estructura
del proyecto, el ambiente de ejecucion basado en Docker y un script que descarga
los datos de **2026**. Todo lo demas debe ser construido por cada equipo.

## Trabajo con fork

El laboratorio se desarrolla y se entrega sobre un **fork** de este repositorio.
No se trabaja directamente sobre el repositorio del docente.

1. Realice un fork de este repositorio:
   <https://github.com/menene/duckdb>

2. Clone **su propio fork** (no el del docente):

   ```bash
   git clone https://github.com/<su-usuario>/duckdb.git
   cd duckdb
   ```

3. Opcional, para recibir correcciones publicadas por el docente:

   ```bash
   git remote add upstream https://github.com/menene/duckdb.git
   git fetch upstream
   ```

Realice commits frecuentes y descriptivos: el historial del repositorio es parte
de la evaluacion. **La entrega del laboratorio es la URL de su fork.**

## Estructura

```text
duckdb/
|
+-- data/
|   +-- raw/
|   +-- processed/
|
+-- notebooks/
|
+-- scripts/
|
+-- sql/
|
+-- docs/
|
+-- Dockerfile
+-- metabase.Dockerfile
+-- docker-compose.yml
+-- README.md
```

## Requisitos

- Docker, con Docker Compose
- Git

La primera construccion del ambiente descarga varios cientos de MB y puede
tardar algunos minutos.

Considere el espacio en disco: las imagenes de Docker ocupan unos 3 GB y los
datos de los tres anios del laboratorio superan 1.5 GB, a los que se suma la
base materializada del Ejercicio 6. Se recomienda tener al menos 10 GB libres.

## Datos

El repositorio incluye `scripts/download_data.py`, que descarga los archivos de
2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
archivos se guardan en `data/raw/<tipo>/<anio>/`.

La TLC publica cada mes con varias semanas de atraso, por lo que los ultimos
meses de 2026 todavia no existen. El script consulta al servidor que meses estan
publicados, de modo que vuelve a ejecutarse sin problema conforme aparezcan
nuevos archivos.

Los datos descargados **no deben incluirse en el repositorio Git**. El archivo
`.gitignore` ya esta configurado para evitarlo.

Fuente de datos: NYC TLC Trip Record Data
<https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page>

Dentro de los contenedores, la carpeta `data/` del proyecto esta montada en
`/workspace/data`. Esa es la ruta que deben usar las herramientas que corren
dentro del ambiente, no la ruta de su computadora.

> **Nota sobre DuckDB:** un archivo `.duckdb` admite un solo proceso con permiso
> de escritura a la vez. Si conecta una herramienta externa a su base de datos,
> use el modo de solo lectura (`read_only`) en esa conexion; de lo contrario los
> demas procesos no podran abrir el archivo.

## Material a entregar

Al finalizar, su fork debe contener:

- el codigo fuente modificado y los scripts de descarga;
- las consultas SQL desarrolladas;
- el notebook o notebooks utilizados;
- la documentacion de las consultas;
- los scripts utilizados para los benchmarks;
- el codigo de los indicadores y visualizaciones;
- el tablero o la evidencia del tablero desarrollado;
- este `README.md`, completado segun la siguiente seccion.

Los archivos de datos descargados **no** deben incluirse.

---

# Documentacion del equipo

Las siguientes secciones deben ser completadas por cada equipo. El README final
debe permitir que una persona que no participo en el desarrollo pueda levantar el
ambiente, descargar los datos, ejecutar el analisis, reproducir los benchmarks y
generar los resultados principales.

## Como levantar el ambiente

1. Clonar el fork y entrar al directorio:

   ```bash
   git clone https://github.com/DiegoOF07/duckdb_lab8.git
   cd duckdb_lab8
   ```

2. Construir las imagenes y levantar los servicios en segundo plano:

   ```bash
   docker compose up -d --build
   ```

3. Verificar que los servicios esten arriba:

   ```bash
   docker compose ps                                # lab8-lab y lab8-metabase en estado "Up"
   curl -s localhost:3000/api/health                # {"status":"ok"} (Metabase tarda ~1 min en iniciar)
   docker compose exec lab python -c "import duckdb; print(duckdb.__version__)"   # 1.5.5
   ```

4. Abrir las herramientas:
   - JupyterLab: <http://localhost:8888> (sin token).
   - Metabase: <http://localhost:3000>.

5. Para detener el ambiente se usa `docker compose down`. Con
   `docker compose down -v` tambien se borra el volumen de Metabase. Los datos
   en `data/` se conservan porque viven en la carpeta del proyecto.

Los comandos del proyecto se ejecutan dentro del contenedor `lab`, con
`docker compose exec lab <comando>`. Dentro del contenedor, el directorio de
trabajo es `/workspace`.

### Herramientas disponibles

| Servicio | Herramienta | Version | Uso |
|---|---|---|---|
| `lab` | Python | 3.11.14 | lenguaje base |
| `lab` | DuckDB (modulo Python) | 1.5.5 | motor SQL analitico. No incluye el CLI `duckdb`; se usa desde Python |
| `lab` | JupyterLab | 4.6.4 | notebooks, puerto 8888 |
| `lab` | pandas / pyarrow | 3.0.6 / 25.0.1 | DataFrames y lectura de Parquet |
| `lab` | matplotlib | 3.11.2 | visualizaciones |
| `lab` | requests, curl | 2.34.2 | descarga de datos |
| `metabase` | Metabase + driver DuckDB | v0.63.19 / 1.5.5.0 | tableros, puerto 3000 (Java 21) |

El contenedor `lab` monta `data/`, `notebooks/`, `scripts/`, `sql/` y `docs/`,
asi que lo que se edita en el host se ve de inmediato dentro del contenedor.
Metabase monta `data/` en `/workspace/data` y guarda su configuracion en el
volumen `metabase-data`.

### Por que un ambiente reproducible

- **Mismos resultados en cualquier maquina.** Las versiones de Python y de cada
  libreria estan fijadas en `Dockerfile` y `requirements.txt`. Una consulta o
  un benchmark da el mismo resultado en la computadora de cualquier integrante
  o del docente, sin depender de lo que cada quien tenga instalado.
- **Compatibilidad entre componentes.** DuckDB 1.5.5 y el driver de Metabase
  deben coincidir, porque un archivo `.duckdb` creado con otra version puede no
  abrirse. El ambiente garantiza esa alineacion.
- **Aislamiento.** No se instala nada en el sistema anfitrion ni se generan
  conflictos con otros proyectos.
- **Trazabilidad y verificacion.** Como el ambiente esta versionado junto con el
  codigo, cualquier persona puede reconstruir exactamente el contexto en que se
  obtuvieron los resultados. Esa es la base de un analisis de datos
  verificable.
- **Arranque rapido.** Un solo comando (`docker compose up`) deja listo todo el
  ambiente para un integrante nuevo.

## Como descargar los datos

<!-- TODO (Ejercicio 8.1) -->

```bash
docker compose exec lab python scripts/download_data.py                     # yellow y green de 2024 y 2026
docker compose exec lab python scripts/download_data.py --anio 2024         # un solo anio
docker compose exec lab python scripts/download_data.py --taxi green        # solo un tipo
```

Los anios del laboratorio estan en la constante `ANIOS` del script (2024 y
2026 desde el Ejercicio 5); `--anio` permite descargar otros. Los archivos se
guardan en `data/raw/<tipo>/<anio>/<tipo>_tripdata_<anio>-MM.parquet` y, al
terminar, el script escribe un manifiesto por anio (`data/raw/manifest_<anio>.csv`)
con el tipo, mes, ruta, bytes, filas y estado de cada archivo. El script puede
ejecutarse cuantas veces sea necesario: solo descarga lo que falta o esta
incompleto, y no toca los archivos de otros anios.

Con 2024 y 2026 se descargan 40 archivos (unos 1.2 GB) con 71,870,407 filas.
Los cambios del Ejercicio 5 y la verificacion de la incorporacion de 2024 estan
en [`docs/ejercicio5.md`](docs/ejercicio5.md).

El script tambien descarga la tabla de zonas de la TLC en
`data/raw/taxi_zone_lookup.csv` (265 zonas con borough y `service_zone`), que
usa el analisis del Ejercicio 4. Si el archivo ya existe, no se vuelve a
descargar.

### Cambios realizados al script (2.6)

El script original ya recorria los 12 meses, consultaba con `HEAD` que archivos
estaban publicados y omitia los que existian localmente. Su limitacion era que
consideraba valido cualquier archivo local de mas de 0 bytes, de modo que un
archivo truncado o corrupto nunca se volvia a descargar. Los cambios son estos:

| Cambio | Motivo |
|---|---|
| `esta_publicado()` se reemplazo por `tamanio_remoto()`, que devuelve el `Content-Length` del servidor o `None` si el mes no esta publicado (403) | conocer el tamano esperado de cada archivo |
| Un archivo local se omite solo si su tamano coincide con el remoto. Si difiere, se reporta como incompleto y se descarga de nuevo | el punto 2.4 no se cumple si se conserva un archivo danado |
| Sin conexion, un archivo local existente se conserva y no se marca como fallido | poder ejecutar el script sin red una vez descargados los datos |
| `descargar_archivo()` verifica que los bytes escritos coincidan con el `Content-Length`; si no, reintenta | detectar descargas cortadas |
| Cada archivo se valida leyendo su footer con `pyarrow.parquet.read_metadata`. Si no es legible se elimina y se reporta como fallido | asegurar que el archivo es un Parquet valido, no solo que pesa lo esperado |
| Se genera `data/raw/manifest_2026.csv` y el resumen muestra el total de filas. Al ejecutarlo con `--taxi` se conservan las filas del otro tipo | dejar evidencia verificable de lo descargado |

Pruebas realizadas dentro del contenedor:

1. La primera ejecucion descargo 16 archivos (8 yellow y 8 green), con 30,040,469 filas.
2. La segunda ejecucion descargo 0 archivos y omitio 16, porque ya existian.
3. Se trunco `green_tripdata_2026-03.parquet` a 1000 bytes. El script lo
   detecto como incompleto (`1000 de 1082530 bytes`) y lo volvio a descargar.

### Como se determino que el conjunto esta completo (2.7)

1. **Meses esperados.** La TLC publica con unos dos meses de atraso. Al
   5 de octubre de 2026, el servidor responde 200 para enero a agosto y 403 para
   septiembre a diciembre, en ambos tipos. El resumen del script lo confirma:
   16 descargados o existentes, 8 no publicados y 0 fallidos.
2. **Integridad de bytes.** Cada archivo local pesa exactamente lo que indica
   el `Content-Length` del servidor.
3. **Integridad del formato.** Los 16 footers Parquet se leyeron sin error, y
   todos los archivos tienen filas (entre 37 mil y 44 mil en green, y entre
   3.3 y 4.1 millones en yellow), sin meses vacios ni atipicamente pequenos.
4. **Contraste independiente.** El conteo con DuckDB (`count(*)` sobre los
   Parquet, consulta 03 del Ejercicio 3) da 30,040,469 filas, igual que el
   manifiesto.

## Como ejecutar el analisis

### Ejercicio 3: exploracion directa sobre Parquet

Las consultas estan en `sql/ejercicio3/` (una por archivo). El notebook
`notebooks/01_exploracion_parquet.ipynb` las ejecuta en orden. Puede abrirse en
JupyterLab, o ejecutarse completo desde la terminal:

```bash
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/01_exploracion_parquet.ipynb
```

La documentacion de cada consulta (SQL, objetivo, fuentes, resultado y
decisiones), los problemas de calidad encontrados y la explicacion de por que
consultar Parquet directamente estan en [`docs/ejercicio3.md`](docs/ejercicio3.md).

### Ejercicio 4: analisis exploratorio

Las consultas estan en `sql/ejercicio4/`. `00_vistas.sql` crea las vistas
`viajes`, `viajes_validos` y `zonas`, con las reglas de calidad del Ejercicio 3,
y las consultas `01` a `17` las reutilizan. El notebook
`notebooks/02_analisis_exploratorio.ipynb` crea las vistas, ejecuta las
consultas en orden y genera las graficas. Requiere la tabla de zonas, que
descarga `scripts/download_data.py`.

```bash
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/02_analisis_exploratorio.ipynb
```

Las preguntas planteadas, la documentacion de cada consulta, la interpretacion
de los resultados y los hallazgos estan en [`docs/ejercicio4.md`](docs/ejercicio4.md).

`00_vistas.sql` tambien limita los archivos temporales de DuckDB a 4 GB y los
dirige a `data/processed/duckdb_tmp/`. Sin ese limite, una consulta que no cabe
en memoria puede llenar el disco virtual de Docker.

### Ejercicio 5: incorporacion de 2024

Las consultas de validacion estan en `sql/ejercicio5/`. El notebook
`notebooks/03_incorporacion_2024.ipynb` verifica los archivos de 2024, consulta
2024 y 2026 de forma conjunta y vuelve a ejecutar todas las consultas de los
Ejercicios 3 y 4 sobre el conjunto ampliado (tarda unos 13 minutos).

```bash
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/03_incorporacion_2024.ipynb
```

La documentacion esta en [`docs/ejercicio5.md`](docs/ejercicio5.md).

## Como reproducir los benchmarks

El benchmark del Ejercicio 6 compara las mismas consultas sobre los Parquet y
sobre tablas materializadas en DuckDB, en tres escalas (un mes, 2026 y todos
los anios descargados). Requiere haber descargado los datos.

```bash
# 1. Materializa las tablas que falten y mide las consultas (unos 10 minutos)
docker compose exec lab python scripts/benchmark.py

# 2. Genera las tablas y graficas de resultados
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/04_benchmark_parquet_vs_duckdb.ipynb
```

- Las tablas se guardan en `data/processed/taxis.duckdb` (unos 2.8 GB, no se
  versiona): `viajes` (todos los anios), `viajes_2026`, `viajes_2026_01` y
  `zonas`. Si se descargan anios nuevos, `--recrear` vuelve a crearlas.
- Los tiempos se escriben en `docs/ejercicio6_benchmark.csv` y el costo de
  materializar en `docs/ejercicio6_materializacion.csv`. Ambos se versionan
  como evidencia.
- El script verifica que cada consulta devuelva el mismo resultado con ambas
  estrategias.
- Las consultas estan en `sql/ejercicio6/`. El diseno, los resultados y su
  analisis estan en [`docs/ejercicio6.md`](docs/ejercicio6.md).

Para conectar otra herramienta (por ejemplo Metabase) a `taxis.duckdb`, use el
modo de solo lectura, como indica la nota sobre DuckDB al inicio de este README.

## Como generar los resultados principales

<!-- TODO -->
