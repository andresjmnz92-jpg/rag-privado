#!/usr/bin/env python3
"""Measures retrieval only: plain vector search against hybrid search.

No LLM is involved. That is the point: the 8 August round scored the whole
pipeline at once, so a wrong answer could not be traced to the retriever or to
the writer. This asks one question — does the right section come back, and in
what position — and it costs nothing to run.

Reads the published SQL from ../sql/busqueda-hibrida.sql instead of carrying a
copy, so what gets measured is what got published.

Run it from the workstation, without leaving a file on the server:

    ssh -i homelab_key aj1604@<host> 'python3 -' < medir-recuperacion.py
"""

import json
import os
import subprocess
import sys
import urllib.request

SQL_HIBRIDA = os.path.expanduser("~/rag-privado/sql/busqueda-hibrida.sql")
POSTGRES = "rag-privado-postgres-1"
OLLAMA = "rag-privado-ollama-1"
MODELO = "bge-m3:latest"

# The 16 questions from the golden dataset that have a known section. The four
# control questions are left out: they have no correct section by design — the
# correct behaviour is silence, which is the writer's job, not the retriever's.
PREGUNTAS = [
    (1, "¿Qué plazo tiene una entidad para notificar a los individuos afectados por una brecha?", ["164.404"]),
    (2, "¿A partir de cuántos individuos afectados hay que notificar a los medios de comunicación?", ["164.406"]),
    (3, "¿Cuándo debe notificarse una brecha al Secretary?", ["164.408"]),
    (4, "¿Qué plazo tiene un business associate para notificar una brecha a la entidad cubierta?", ["164.410"]),
    (5, "¿Cuántos años deben conservarse las políticas y procedimientos de seguridad?", ["164.316"]),
    (6, "¿Cuál es la definición de business associate?", ["160.103"]),
    (7, "¿Cuál es la definición de breach?", ["164.402"]),
    (8, "¿Cuáles son las tres categorías de salvaguardas de la Security Rule?", ["164.308", "164.310", "164.312"]),
    (9, "¿Qué plazo hay para darle a un individuo acceso a su información de salud?", ["164.524"]),
    (10, "¿Qué plazo hay para responder a una solicitud de enmienda?", ["164.526"]),
    (11, "¿Qué período cubre el accounting of disclosures?", ["164.528"]),
    (12, "¿Cuáles son los montos de las multas civiles por violación?", ["160.404"]),
    (13, "¿Qué factores se consideran para determinar el monto de una multa?", ["160.408"]),
    (14, "¿Qué elementos debe contener la notificación de brecha a los individuos?", ["164.404"]),
    (15, "¿Qué debe incluir el Notice of Privacy Practices?", ["164.520"]),
    (16, "¿En qué casos NO aplica el estándar de minimum necessary?", ["164.502"]),
]

SQL_VECTORIAL = """
SELECT metadata->>'seccion'
FROM documentos_v2
ORDER BY embedding <=> :'vec'::vector
LIMIT 10;
"""


def ip_ollama():
    """Ask Docker for the address instead of hardcoding it — it changes on restart."""
    fmt = "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}"
    salida = subprocess.run(
        ["docker", "inspect", "-f", fmt, OLLAMA],
        capture_output=True, text=True, check=True,
    )
    return salida.stdout.split()[0]


def vectorizar(texto, host):
    cuerpo = json.dumps({"model": MODELO, "input": texto}).encode("utf-8")
    peticion = urllib.request.Request(
        f"http://{host}:11434/api/embed",
        data=cuerpo,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(peticion, timeout=120) as respuesta:
        datos = json.load(respuesta)
    vectores = datos.get("embeddings") or []
    if not vectores:
        # Ollama answers 200 with an empty list when the input is empty. Green
        # node, no content — the failure that cost an evening on 9 August.
        raise RuntimeError(f"Ollama devolvio embeddings vacio para: {texto!r}")
    return "[" + ",".join(str(x) for x in vectores[0]) + "]"


def psql(sql, vec, q=""):
    """Values travel as docker -e variables, never through a shell string.

    Building the command as text and quoting the question into it looks simpler
    and is a trap: a Spanish question carries ¿ and accents, and json.dumps
    escapes them to \\u00bf, which sh passes through literally.
    """
    # ON_ERROR_STOP is not optional here. Without it psql prints the error and
    # exits 0, so a broken query reads as "returned no rows" — which is a
    # legitimate-looking answer, and scored a clean 0/16 before this was found.
    guion = (
        'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -v ON_ERROR_STOP=1 '
        '-v vec="$VEC" -v q="$Q" -f -'
    )
    salida = subprocess.run(
        ["docker", "exec", "-i", "-e", f"VEC={vec}", "-e", f"Q={q}", POSTGRES, "sh", "-c", guion],
        input=sql, capture_output=True, text=True, encoding="utf-8",
    )
    if salida.returncode != 0:
        raise RuntimeError(salida.stderr.strip())
    return [linea.split("|")[0] for linea in salida.stdout.strip().splitlines() if linea]


def puesto(secciones, esperadas):
    """Position of the first expected section, 1-based. None if it never shows."""
    for i, seccion in enumerate(secciones, start=1):
        if seccion in esperadas:
            return i
    return None


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    host = ip_ollama()
    with open(SQL_HIBRIDA, encoding="utf-8") as f:
        publicada = f.read().replace("$1", ":'vec'").replace("$2", ":'q'")

    # The published query returns text first, and that text carries newlines and
    # pipes — reading psql output positionally against it silently compares
    # paragraphs to section numbers and scores a flawless zero. Wrapping it to
    # return one column removes the guesswork. The outer ORDER BY is not
    # decoration: a subquery's row order is not guaranteed without it, and the
    # whole measurement is about position.
    #
    # Comments go first, then the cut. Splitting on the last ';' looks right and
    # is wrong: one of the closing comments contains a semicolon, so the cut
    # landed past the query and left `LIMIT 10;` inside the parentheses.
    sin_comentarios = "\n".join(
        linea for linea in publicada.splitlines() if not linea.strip().startswith("--")
    )
    consulta = sin_comentarios.split(";", 1)[0]
    sql_hibrida = f"SELECT h.seccion FROM ({consulta}) h ORDER BY h.puntaje DESC;"

    filas = []
    for numero, pregunta, esperadas in PREGUNTAS:
        vec = vectorizar(pregunta, host)
        v = psql(SQL_VECTORIAL, vec)
        h = psql(sql_hibrida, vec, pregunta)
        filas.append({
            "n": numero,
            "esperada": "/".join(esperadas),
            "vectorial": puesto(v, esperadas),
            "hibrida": puesto(h, esperadas),
            "encontradas_vectorial": len(set(v) & set(esperadas)),
            "encontradas_hibrida": len(set(h) & set(esperadas)),
        })
        print(f"  {numero}/16 listo", file=sys.stderr)

    def marca(p):
        return str(p) if p else "—"

    print("\n| # | § esperado | Puesto vectorial | Puesto híbrida | Cambio |")
    print("|---|---|---|---|---|")
    for f in filas:
        if f["vectorial"] and f["hibrida"]:
            delta = f["vectorial"] - f["hibrida"]
            cambio = f"+{delta}" if delta > 0 else (str(delta) if delta < 0 else "=")
        elif f["hibrida"] and not f["vectorial"]:
            cambio = "recuperada"
        elif f["vectorial"] and not f["hibrida"]:
            cambio = "perdida"
        else:
            cambio = "ninguna la encuentra"
        print(f"| {f['n']} | {f['esperada']} | {marca(f['vectorial'])} | {marca(f['hibrida'])} | {cambio} |")

    def recall(clave):
        return sum(1 for f in filas if f[clave])

    def mrr(clave):
        return sum(1 / f[clave] for f in filas if f[clave]) / len(filas)

    print(f"\nRecall@10  — vectorial {recall('vectorial')}/16, híbrida {recall('hibrida')}/16")
    print(f"MRR        — vectorial {mrr('vectorial'):.3f}, híbrida {mrr('hibrida'):.3f}")
    print(json.dumps(filas, ensure_ascii=False))


if __name__ == "__main__":
    main()
