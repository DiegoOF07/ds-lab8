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

<!-- TODO (Ejercicios 5.1 y 8.1) -->

```bash
docker compose exec lab python scripts/download_data.py                # yellow y green 2026
docker compose exec lab python scripts/download_data.py --taxi green   # solo un tipo
```

Los archivos se guardan en `data/raw/<tipo>/2026/<tipo>_tripdata_2026-MM.parquet`.
Al terminar, el script escribe `data/raw/manifest_2026.csv` con el tipo, mes,
ruta, bytes, filas y estado de cada archivo. El script puede ejecutarse
cuantas veces sea necesario: solo descarga lo que falta o esta incompleto.

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

<!-- TODO -->

## Como reproducir los benchmarks

<!-- TODO (Ejercicio 6) -->

## Como generar los resultados principales

<!-- TODO -->
