#!/usr/bin/env python3
"""Crea o actualiza el tablero de los Ejercicios 7 y 8 en Metabase mediante su API.

Cada indicador es una pregunta SQL nativa cuyo texto es el archivo
sql/ejercicio7/i*.sql o sql/ejercicio8/i*.sql correspondiente. El script hace la configuración inicial
de Metabase si falta, registra data/processed/tablero.duckdb en solo lectura y
crea o actualiza las preguntas y el tablero. Volver a ejecutarlo no duplica nada.

Requiere haber ejecutado antes scripts/construir_tablero.py.
"""

import argparse
import os
import sys
import time
from pathlib import Path

import requests

DIR_SQL = Path("sql")
NOMBRE_BASE = "Taxis NYC (tablero)"
NOMBRE_COLECCION = "Lab 8 - Indicadores"
NOMBRE_TABLERO = "Taxis de Nueva York: indicadores"

# Tipos de taxi con los colores del notebook 02; años y categorías con una
# paleta categórica validada para daltonismo, en orden fijo.
AMARILLO, VERDE = "#eda100", "#008300"
AZUL, NARANJA, AGUA, VIOLETA, ROJO, GRIS = (
    "#2a78d6", "#eb6834", "#1baf7a", "#4a3aa7", "#e34948", "#a3a29c")
COLOR_ANIO = {"2024": AZUL, "2025": NARANJA, "2026": AGUA}
RAMPA_AZUL = ["#86b6ef", "#3987e5", "#1c5cab", "#0d366b"]   # tramos ordenados


def series(colores: dict) -> dict:
    return {clave: {"color": color} for clave, color in colores.items()}


def linea(x, metrica, serie, titulo_x, titulo_y, colores) -> dict:
    # Sin rango manual: Metabase ya parte de 0 y fijar el mínimo obliga a fijar el máximo
    return {
        "graph.dimensions": [x, serie], "graph.metrics": [metrica],
        "graph.x_axis.title_text": titulo_x, "graph.y_axis.title_text": titulo_y,
        "graph.x_axis.scale": "ordinal", "series_settings": colores,
    }


def barras(metricas: dict, titulo_y: str) -> dict:
    """Barras agrupadas, una serie por columna: {columna: (título, color)}."""
    return {
        "graph.dimensions": ["grupo"], "graph.metrics": list(metricas),
        "graph.show_values": True, "graph.x_axis.title_text": "", "graph.y_axis.title_text": titulo_y,
        "series_settings": {c: {"title": t, "color": color} for c, (t, color) in metricas.items()},
    }


def barras_por_categoria(categoria, metrica, titulo_y, colores, apiladas=True) -> dict:
    ajustes = {
        "graph.dimensions": ["grupo", categoria], "graph.metrics": [metrica],
        "graph.x_axis.title_text": "", "graph.y_axis.title_text": titulo_y,
        "series_settings": series(colores),
    }
    if apiladas:
        ajustes |= {"stackable.stack_type": "stacked", "graph.y_axis.auto_range": False,
                    "graph.y_axis.min": 0, "graph.y_axis.max": 100}
    else:
        ajustes["graph.show_values"] = True
    return ajustes


def columnas(titulos: dict) -> dict:
    return {"column_settings": {f'["name","{c}"]': {"column_title": t} for c, t in titulos.items()}}


# ancho y alto usan la cuadrícula de 24 columnas de Metabase.
INDICADORES = [
    {"archivo": "i01_resumen_anual", "display": "table", "ancho": 24, "alto": 5,
     "titulo": "I1. Resumen por tipo y año (meses comunes)",
     "visualizacion": columnas({
         "tipo": "Tipo", "anio": "Año", "meses": "Meses", "viajes_por_dia": "Viajes por día",
         "ingresos_por_dia_miles_usd": "Ingresos por día (miles USD)",
         "total_mediano_usd": "Total mediano (USD)", "distancia_mediana_mi": "Distancia mediana (mi)",
         "duracion_mediana_min": "Duración mediana (min)"}),
     "interpretacion": "Yellow llega a su máximo en 2025 (+18% sobre 2024) y baja 5% en 2026. "
                       "Green cae todos los años (-10% y -14%)."},
    {"archivo": "i02a_demanda_yellow", "display": "line", "ancho": 12, "alto": 7,
     "titulo": "I2a. Viajes por día en cada mes, taxis amarillos",
     "visualizacion": linea("mes", "viajes_por_dia", "anio", "mes", "viajes por día", series(COLOR_ANIO)),
     "interpretacion": "2025 supera a 2024 en todos los meses. 2026 queda por debajo de 2025 de "
                       "febrero a agosto (2% a 10%). Misma estacionalidad."},
    {"archivo": "i02b_demanda_green", "display": "line", "ancho": 12, "alto": 7,
     "titulo": "I2b. Viajes por día en cada mes, taxis verdes",
     "visualizacion": linea("mes", "viajes_por_dia", "anio", "mes", "viajes por día", series(COLOR_ANIO)),
     "interpretacion": "Cada año queda por debajo del anterior en todos los meses."},
    {"archivo": "i03_perfil_horario", "display": "line", "ancho": 12, "alto": 7,
     "titulo": "I3. Perfil horario de la demanda (% de viajes por hora)",
     "visualizacion": linea("hora", "pct_viajes", "serie", "hora de inicio", "% de viajes", {
         "yellow laboral": {"color": AMARILLO},
         "yellow fin de semana": {"color": AMARILLO, "line.style": "dashed"},
         "green laboral": {"color": VERDE},
         "green fin de semana": {"color": VERDE, "line.style": "dashed"}}),
     "interpretacion": "Green tiene picos de traslado al trabajo (8 y 17 h). Yellow sigue alto "
                       "hasta las 22 h y concentra la noche del fin de semana."},
    {"archivo": "i04_velocidad_hora", "display": "line", "ancho": 12, "alto": 7,
     "titulo": "I4. Velocidad mediana por hora en el centro de Manhattan (yellow, días laborales)",
     "visualizacion": linea("hora", "velocidad_mediana_mph", "anio", "hora de inicio", "mph",
                            series(COLOR_ANIO)),
     "interpretacion": "De día se circula a unas 7 mph. 2025 es igual a 2024 (±2%) pese al cargo "
                       "por congestión; 2026 es más lento en todas las horas."},
    {"archivo": "i05_costo_viaje", "display": "bar", "ancho": 12, "alto": 7,
     "titulo": "I5. Total mediano por viaje según el canal (USD)",
     "visualizacion": barras_por_categoria("canal", "total_mediano_usd", "USD",
                                           {"Taxímetro": AZUL, "Aplicación": NARANJA}, apiladas=False),
     "interpretacion": "En yellow, la aplicación cuesta 6% más que el taxímetro en 2024 y 2025, "
                       "y 32% más en 2026."},
    {"archivo": "i06_formas_pago", "display": "bar", "ancho": 12, "alto": 7,
     "titulo": "I6. Formas de pago (% de viajes)",
     "visualizacion": barras_por_categoria("forma", "pct_viajes", "% de viajes", {
         "Tarjeta": AZUL, "Efectivo": NARANJA, "Aplicación": AGUA, "Otros": VIOLETA}),
     "interpretacion": "La aplicación en yellow salta de 9% a 22% en 2025 y llega a 25% en 2026. "
                       "En green crece después: 4%, 7% y 15%."},
    {"archivo": "i07_propinas", "display": "bar", "ancho": 12, "alto": 7,
     "titulo": "I7. Propina sobre la tarifa, pagos con tarjeta (% de viajes)",
     "visualizacion": barras_por_categoria("tramo", "pct_viajes", "% de viajes con tarjeta", dict(zip(
         ["1. sin propina", "2. menos de 20%", "3. 20% a 25%", "4. 25% a 30%", "5. 30% o más"],
         [GRIS] + RAMPA_AZUL))),
     "interpretacion": "Más del 70% deja 20% o más. En yellow, el 30% o más sube en 2025 y los "
                       "viajes sin propina crecen cada año."},
    {"archivo": "i08_aeropuertos", "display": "bar", "ancho": 12, "alto": 7,
     "titulo": "I8. Peso de los viajes de aeropuerto (%)",
     "visualizacion": barras({"pct_viajes": ("% de viajes", AZUL),
                              "pct_ingresos": ("% de ingresos", NARANJA)}, "%"),
     "interpretacion": "Su peso en los ingresos de yellow baja cada año: 28%, 25% y 21%."},
    {"archivo": "i09_zona_origen", "display": "bar", "ancho": 24, "alto": 7,
     "titulo": "I9. Zona de origen de los viajes (% de viajes)",
     "visualizacion": barras_por_categoria("origen", "pct_viajes", "% de viajes", {
         "Manhattan centro (Yellow Zone)": AZUL, "Alto Manhattan": NARANJA, "Brooklyn": AGUA,
         "Queens": VIOLETA, "Resto": ROJO}),
     "interpretacion": "Los mercados siguen separados, pero yellow duplica su peso fuera del "
                       "centro en 2025 (de 4.6% a 9.1%) y lo mantiene en 2026."},
    {"archivo": "i11_aplicacion_mensual", "display": "line", "ancho": 12, "alto": 7,
     "titulo": "I11. Viajes por aplicación (% por mes)",
     "visualizacion": {"graph.dimensions": ["mes", "tipo"], "graph.metrics": ["pct_aplicacion"],
                       "graph.x_axis.title_text": "", "graph.y_axis.title_text": "% de viajes",
                       "series_settings": series({"yellow": AMARILLO, "green": VERDE})},
     "interpretacion": "En yellow salta en enero y febrero de 2025 (de 8% a 22%) y queda entre 18% "
                       "y 29%. En green crece desde junio de 2025 hasta 15%."},
    {"archivo": "i12_velocidad_mensual", "display": "line", "ancho": 12, "alto": 7,
     "titulo": "I12. Velocidad mediana por mes en el centro de Manhattan (yellow, días laborales, 5 a 21 h)",
     "visualizacion": {"graph.dimensions": ["mes"], "graph.metrics": ["velocidad_mediana_mph"],
                       "graph.x_axis.title_text": "", "graph.y_axis.title_text": "mph",
                       "series_settings": {"velocidad_mediana_mph": {"color": AZUL, "title": "mph"}}},
     "interpretacion": "Sin salto en enero de 2025: cada mes de 2025 queda a menos de 2.5% del "
                       "mismo mes de 2024. 2026 es entre 4% y 12% más lento que 2025."},
    {"archivo": "i10_calidad_mensual", "display": "line", "ancho": 24, "alto": 6,
     "titulo": "I10. Registros excluidos por las reglas de calidad (% por mes)",
     "visualizacion": {"graph.dimensions": ["mes", "tipo"], "graph.metrics": ["pct_excluidos"],
                       "graph.x_axis.title_text": "", "graph.y_axis.title_text": "% excluidos",
                       "series_settings": series({"yellow": AMARILLO, "green": VERDE})},
     "interpretacion": "Entre 2.4% y 6.4% por mes, sin saltos que invaliden la comparación."},
]

ENCABEZADO = """# Taxis de Nueva York: indicadores

Viajes válidos de taxis amarillos (yellow) y verdes (green) de la TLC, desde `data/processed/tablero.duckdb`.
Cada tarjeta es una consulta de `sql/ejercicio7/` o `sql/ejercicio8/`; su interpretación está en el ícono de información y en `docs/`."""

SECCIONES = {
    "i01_resumen_anual": "## Tamaño de cada servicio",
    "i02a_demanda_yellow": "## Cuándo se viaja",
    "i05_costo_viaje": "## Precio, pago e ingresos",
    "i09_zona_origen": "## Dónde se viaja",
    "i11_aplicacion_mensual": "## Evolución mensual",
    "i10_calidad_mensual": "## Calidad de los datos",
}

HALLAZGOS = """## Hallazgos

1. Yellow llega a su máximo en 2025 y baja 5% en 2026; green cae todos los años (I1, I2).
2. En 2025 la aplicación salta de 9% a 22% de yellow, a la vez que yellow duplica su peso fuera del centro (I6, I9, I11).
3. El sobreprecio de la aplicación llega después: 6% en 2024 y 2025, 32% en 2026 (I5).
4. El cargo por congestión no mejora la velocidad: 2025 es igual a 2024 y 2026 más lento (I4, I12).
5. Green atiende traslados al trabajo; yellow, además, la vida nocturna (I3)."""


class Metabase:
    def __init__(self, url: str):
        self.url = url.rstrip("/")
        self.sesion = requests.Session()

    def llamar(self, metodo: str, ruta: str, **kwargs):
        respuesta = self.sesion.request(metodo, f"{self.url}/api/{ruta}", timeout=120, **kwargs)
        if not respuesta.ok:
            raise RuntimeError(f"{metodo} /api/{ruta}: {respuesta.status_code} {respuesta.text[:500]}")
        return respuesta.json() if respuesta.content else None

    def esperar(self, segundos: int = 300) -> None:
        """Metabase tarda alrededor de un minuto en iniciar."""
        limite = time.monotonic() + segundos
        while time.monotonic() < limite:
            try:
                if self.sesion.get(f"{self.url}/api/health", timeout=5).json().get("status") == "ok":
                    return
            except (requests.RequestException, ValueError):
                pass
            time.sleep(3)
        raise RuntimeError(f"Metabase no respondió en {self.url} después de {segundos} s")

    def iniciar_sesion(self, email: str, password: str) -> None:
        propiedades = self.llamar("GET", "session/properties")
        if not propiedades.get("has-user-setup"):
            print("  configuración inicial de Metabase: se crea el usuario administrador")
            sesion = self.llamar("POST", "setup", json={
                "token": propiedades["setup-token"],
                "user": {"email": email, "password": password, "first_name": "Lab",
                         "last_name": "DuckDB", "site_name": "Lab 8 DuckDB"},
                "prefs": {"site_name": "Lab 8 DuckDB", "site_locale": "es", "allow_tracking": False},
            })
        else:
            sesion = self.llamar("POST", "session", json={"username": email, "password": password})
        self.sesion.headers["X-Metabase-Session"] = sesion["id"]


def registrar_base(mb: Metabase, ruta_base: str) -> int:
    # memory_limit evita que DuckDB compita por memoria con la JVM de Metabase
    detalles = {"database_file": ruta_base, "read_only": True, "memory_limit": "2GB"}
    for base in mb.llamar("GET", "database")["data"]:
        if base["name"] == NOMBRE_BASE:
            mb.llamar("PUT", f"database/{base['id']}", json={"details": detalles})
            print(f"  base '{NOMBRE_BASE}' ya registrada (id {base['id']})")
            return base["id"]
    base = mb.llamar("POST", "database", json={"engine": "duckdb", "name": NOMBRE_BASE,
                                               "details": detalles})
    print(f"  base '{NOMBRE_BASE}' registrada (id {base['id']})")
    return base["id"]


def obtener_coleccion(mb: Metabase) -> int:
    for coleccion in mb.llamar("GET", "collection"):
        if coleccion.get("name") == NOMBRE_COLECCION and not coleccion.get("archived"):
            return coleccion["id"]
    return mb.llamar("POST", "collection", json={"name": NOMBRE_COLECCION, "parent_id": None})["id"]


def items(mb: Metabase, id_coleccion: int, modelo: str) -> dict:
    datos = mb.llamar("GET", f"collection/{id_coleccion}/items", params={"models": modelo})["data"]
    return {item["name"]: item["id"] for item in datos}


def pregunta_del_sql(sql: str) -> str:
    """Pregunta de análisis, tomada del comentario `-- Pregunta:` del archivo SQL."""
    for linea_sql in sql.splitlines():
        if linea_sql.startswith("-- Pregunta:"):
            texto = linea_sql.removeprefix("-- Pregunta:").strip()
            return texto[0].upper() + texto[1:]
    return ""


def guardar_preguntas(mb: Metabase, id_base: int, id_coleccion: int) -> dict:
    existentes = items(mb, id_coleccion, "card")
    ids = {}
    for ind in INDICADORES:
        sql = next(DIR_SQL.glob(f"ejercicio*/{ind['archivo']}.sql")).read_text()
        pregunta = {
            "name": ind["titulo"],
            "description": f"{pregunta_del_sql(sql)} {ind['interpretacion']}",
            "display": ind["display"], "collection_id": id_coleccion,
            "visualization_settings": ind["visualizacion"],
            "dataset_query": {"type": "native", "database": id_base, "native": {"query": sql}},
        }
        if ind["titulo"] in existentes:
            ids[ind["archivo"]] = existentes.pop(ind["titulo"])
            mb.llamar("PUT", f"card/{ids[ind['archivo']]}", json=pregunta)
            accion = "actualizada"
        else:
            ids[ind["archivo"]] = mb.llamar("POST", "card", json=pregunta)["id"]
            accion = "creada"
        print(f"  {ind['titulo'][:72]:<74} {accion}")
    # Preguntas de la colección que ya no corresponden a ningún indicador (p. ej. renombradas)
    for nombre, id_pregunta in existentes.items():
        mb.llamar("PUT", f"card/{id_pregunta}", json={"archived": True})
        print(f"  {nombre[:72]:<74} archivada")
    return ids


def tarjeta_texto(id_tarjeta: int, texto: str, fila: int, alto: int) -> dict:
    return {
        "id": id_tarjeta, "card_id": None, "row": fila, "col": 0, "size_x": 24, "size_y": alto,
        "visualization_settings": {
            "virtual_card": {"name": None, "display": "text", "visualization_settings": {},
                             "dataset_query": {}, "archived": False},
            "text": texto,
        },
    }


def disponer_tarjetas(ids: dict) -> list:
    """Ubica textos y preguntas en la cuadrícula, de arriba hacia abajo."""
    tarjetas, fila, col, alto_fila = [], 0, 0, 0
    # Ids negativos: Metabase crea tarjetas nuevas y descarta las que no están en la lista
    siguiente_id = iter(range(-1, -1000, -1))

    def texto(contenido: str, alto: int) -> None:
        nonlocal fila
        tarjetas.append(tarjeta_texto(next(siguiente_id), contenido, fila, alto))
        fila += alto

    texto(ENCABEZADO, 2)
    for ind in INDICADORES:
        nueva_seccion = ind["archivo"] in SECCIONES
        if col and (nueva_seccion or col + ind["ancho"] > 24):
            fila, col = fila + alto_fila, 0
        if nueva_seccion:
            texto(SECCIONES[ind["archivo"]], 1)
        tarjetas.append({"id": next(siguiente_id), "card_id": ids[ind["archivo"]], "row": fila,
                         "col": col, "size_x": ind["ancho"], "size_y": ind["alto"],
                         "visualization_settings": {}})
        col, alto_fila = col + ind["ancho"], ind["alto"]
    fila += alto_fila
    texto(HALLAZGOS, 5)
    return tarjetas


def guardar_tablero(mb: Metabase, id_coleccion: int, ids: dict) -> int:
    id_tablero = items(mb, id_coleccion, "dashboard").get(NOMBRE_TABLERO)
    if id_tablero is None:
        id_tablero = mb.llamar("POST", "dashboard", json={
            "name": NOMBRE_TABLERO, "collection_id": id_coleccion})["id"]
    mb.llamar("PUT", f"dashboard/{id_tablero}", json={
        "description": "Indicadores de los Ejercicios 7 y 8 (CC3084 Lab 8). Consultas en sql/ejercicio7/ y sql/ejercicio8/.",
        "width": "full", "dashcards": disponer_tarjetas(ids)})
    return id_tablero


def main() -> int:
    parser = argparse.ArgumentParser(description="Crea el tablero de los Ejercicios 7 y 8 en Metabase.")
    parser.add_argument("--url", default="http://metabase:3000", help="URL de Metabase")
    parser.add_argument("--ruta-base", default="/workspace/data/processed/tablero.duckdb",
                        help="ruta de tablero.duckdb vista desde el contenedor de Metabase")
    parser.add_argument("--email", default=os.environ.get("MB_EMAIL", "lab8@example.com"))
    parser.add_argument("--password", default=os.environ.get("MB_PASSWORD", "lab8-duckdb-2026"))
    argumentos = parser.parse_args()

    mb = Metabase(argumentos.url)
    print(f"Conectando con {argumentos.url}")
    mb.esperar()
    mb.iniciar_sesion(argumentos.email, argumentos.password)
    id_base = registrar_base(mb, argumentos.ruta_base)
    id_coleccion = obtener_coleccion(mb)
    print("Preguntas:")
    ids = guardar_preguntas(mb, id_base, id_coleccion)
    id_tablero = guardar_tablero(mb, id_coleccion, ids)
    print(f"\nTablero listo: {argumentos.url}/dashboard/{id_tablero}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
