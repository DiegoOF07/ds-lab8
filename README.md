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

<!-- TODO (Ejercicios 2.6, 5.1 y 8.1) -->

## Como ejecutar el analisis

<!-- TODO -->

## Como reproducir los benchmarks

<!-- TODO (Ejercicio 6) -->

## Como generar los resultados principales

<!-- TODO -->
