"""Genera assets/data/es_municipios.json a partir del volcado de GeoNames.org
para España (licencia CC BY 4.0 — ver el crédito "GeoNames.org" en el footer
de ProfileSheet, lib/screens/profile_sheet.dart).

Por qué existe: search.json de WeatherAPI (usado por PlaceSearchService) es un
buscador difuso con cobertura pobre para municipios españoles pequeños o
medianos (p. ej. "Ibi", "Sant Boi de Llobregat", "L'Alcúdia" no aparecían o
devolvían coincidencias erróneas de otros países). Este listado local se
consulta en paralelo con priorida sobre WeatherAPI (ver
SpanishMunicipalitiesService y PlaceSearchService.search).

Uso (regenerar el dataset, p. ej. si GeoNames publica una versión más
reciente):
    python tools/generar_es_municipios.py

Requiere solo la librería estándar de Python 3. Descarga ~3,3 MB (ES.zip) +
~2,4 MB (admin2Codes.txt) de download.geonames.org y escribe
assets/data/es_municipios.json (~525 KB).
"""

from __future__ import annotations

import csv
import io
import json
import re
import sys
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "assets" / "data" / "es_municipios.json"

ES_ZIP_URL = "https://download.geonames.org/export/dump/ES.zip"
ADMIN2_URL = "https://download.geonames.org/export/dump/admin2Codes.txt"

# Sedes administrativas conocidas: capital de país/comunidad/provincia/comarca
# o municipio. Se aceptan aunque su población salga a 0 (GeoNames a veces la
# atribuye a la entidad ADM en vez de al punto poblado).
SEAT_CODES = {"PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4"}
# Abandonado / destruido / histórico: nunca son una localidad habitable hoy.
EXCLUDED_CODES = {"PPLQ", "PPLW", "PPLH"}

_PROVINCE_PREFIX = re.compile(r"^(Provincia de|Prov[íi]ncia de|Province of)\s+", re.IGNORECASE)


def _fetch(url: str) -> bytes:
    print(f"Descargando {url} ...", file=sys.stderr)
    with urllib.request.urlopen(url, timeout=60) as resp:
        return resp.read()


def _load_provinces() -> dict[str, str]:
    raw = _fetch(ADMIN2_URL).decode("utf-8")
    provinces: dict[str, str] = {}
    for line in raw.splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or not parts[0].startswith("ES."):
            continue
        provinces[parts[0]] = _PROVINCE_PREFIX.sub("", parts[1]).strip()
    print(f"Provincias ES cargadas: {len(provinces)}", file=sys.stderr)
    return provinces


def _load_es_txt() -> str:
    zip_bytes = _fetch(ES_ZIP_URL)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        return zf.read("ES.txt").decode("utf-8")


def main() -> None:
    provinces = _load_provinces()
    es_txt = _load_es_txt()

    rows: list[dict] = []
    reader = csv.reader(io.StringIO(es_txt), delimiter="\t")
    for r in reader:
        if len(r) < 15:
            continue
        (_geonameid, name, _asciiname, _alt, lat, lon, feature_class, feature_code,
         _cc, _cc2, admin1, admin2, _admin3, _admin4, population) = r[:15]
        if feature_class != "P" or not feature_code.startswith("PPL"):
            continue
        if feature_code in EXCLUDED_CODES:
            continue
        pop = int(population) if population else 0
        if feature_code not in SEAT_CODES and pop <= 0:
            continue
        province = provinces.get(f"ES.{admin1}.{admin2}", "")
        rows.append({
            "name": name,
            "lat": round(float(lat), 4),
            "lon": round(float(lon), 4),
            "province": province,
            "population": pop,
        })

    print(f"Localidades candidatas: {len(rows)}", file=sys.stderr)

    # Mismo nombre + misma provincia (raro): se queda la de mayor población.
    dedup: dict[tuple[str, str], dict] = {}
    for row in rows:
        key = (row["name"], row["province"])
        if key not in dedup or row["population"] > dedup[key]["population"]:
            dedup[key] = row

    final_rows = sorted(dedup.values(), key=lambda r: (r["name"], r["province"]))
    dup_names = sum(1 for c in Counter(r["name"] for r in final_rows).values() if c > 1)
    print(f"Localidades finales: {len(final_rows)} ({dup_names} nombres repetidos "
          "entre provincias, desambiguados en la app por displayName)", file=sys.stderr)

    out = [{"n": r["name"], "p": r["province"], "lat": r["lat"], "lon": r["lon"]}
           for r in final_rows]

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    print(f"Escrito {OUT_PATH} ({OUT_PATH.stat().st_size / 1024:.0f} KB, {len(out)} localidades)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
