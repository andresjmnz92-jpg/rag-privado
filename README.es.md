*[English](README.md) · **Español***

# RAG privado — medido, no demostrado

Un sistema de recuperación aumentada por generación que corre entero en mi propio servidor, hecho
para responder preguntas sobre documentos normativos **sin que los documentos salgan nunca de la
máquina**.

Lo que este repo quiere mostrar no es que funciona. Es que **medí qué tan bien funciona, encontré
dónde se rompe, y puedo probar cuál de los arreglos valía la pena**.

**Stack:** PostgreSQL 17 + pgvector · Ollama con BGE-M3 (local, solo CPU) · n8n ·
`gpt-5-mini` para redactar
**Servidor:** Hetzner CX33 — 4 vCPU, 8 GB de RAM, sin GPU · ~$9 al mes
**Corpus:** HIPAA Administrative Simplification, 45 CFR partes 160, 162 y 164 — 115 páginas

---

## La decisión de arquitectura que importa

**Los embeddings corren en local. Solo los fragmentos recuperados salen del servidor.**

Ese es el argumento entero para una clínica o un laboratorio: el documento nunca se sube a ningún
lado. BGE-M3 lo convierte en vectores en la misma máquina que los guarda. Postgres y Ollama no
publican puertos — solo se alcanzan desde dentro de la red de Docker.

Una segunda decisión que no cuesta nada y evita una caída: **este stack tiene su propio archivo de
compose**, separado de la instancia de n8n donde corre el bot de un cliente. Bajar el RAG para
mantenimiento no puede dejar a un cliente sin servicio.

**La búsqueda cruza idiomas.** Todas las preguntas de abajo se hicieron en español contra un
documento en inglés. BGE-M3 es multilingüe, y la recuperación funcionó en los 20 casos.

---

## Resultados

20 preguntas con la respuesta verificada a mano contra el PDF original — 16 con respuesta conocida,
y **4 preguntas de control cuya respuesta correcta es que el sistema diga que no sabe**.

| | topK = 5 | topK = 20 |
|---|---|---|
| Completas y correctas | 7 | **11** |
| Incompletas pero sin errores | 7 | 3 |
| Con una cifra equivocada | 1 | 1 |
| Falso negativo (se calló teniendo la respuesta) | 0 | **1** |
| Preguntas de control superadas | **4 / 4** | **4 / 4** |
| **Alucinaciones** | **0** | **0** |
| **Puntaje estricto** | **11/20 — 55%** | **15/20 — 75%** |

**Latencia**, sobre 23 ejecuciones: mediana 16 s · promedio 18 s · peor caso completado 262 s · un
timeout a los 604 s.

**Indexación:** 577 fragmentos en 8 min 8 s, en 4 vCPU sin GPU — unas 14 páginas por minuto. Se
paga una sola vez.

---

## Lo que encontró la evaluación

**Cero alucinaciones en 20 preguntas.** Las cuatro de control se respondieron con *"No encontré eso
en los documentos cargados"* — incluida una trampa que preguntaba el precio de la certificación
oficial de HIPAA, que no existe. Para un comprador del sector salud ese es el número que importa:
un sistema que se calla es auditable; uno que improvisa es un riesgo legal.

**Subir `topK` de 5 a 20 arregló cuatro respuestas y rompió una.** La pregunta 16 pasó de
parcialmente correcta a *"No encontré eso"* — con veinte fragmentos en el contexto, la señal quedó
enterrada en ruido. **El óptimo no está en ninguno de los dos extremos**, y eso solo aparece si
uno vuelve a correr las preguntas que ya funcionaban.

**Un error que ningún lector habría detectado.** A la pregunta de a partir de cuántos afectados hay
que avisar a los medios, el sistema respondió *"a partir de 500"* mientras citaba el texto que él
mismo había recuperado: *"more than 500 residents"*. Una brecha que afecte exactamente a 500
personas **no** obliga a avisar a los medios. La recuperación fue correcta; el resumen, no. Ese
tipo de error es invisible salvo que compares cada respuesta contra la fuente — que es justamente
para lo que sirve la evaluación.

**Los fallos de recuperación y los de generación se arreglan al revés.** La pregunta 14 falló
porque los fragmentos con la respuesta nunca llegaron al modelo. La 2 falló con el texto correcto
delante. El chunking arregla la primera; el prompt arregla la segunda. Mirando solo la respuesta
final, las dos se ven igual de "incompletas".

---

## Método: medir antes de construir

Durante este proyecto se propusieron tres arreglos caros. **Dos estaban equivocados, y medir es lo
que lo demostró.**

**"Los fragmentos están cortados a mitad de lista — hay que reindexar con otra estrategia."**
Sonaba bien, venía con evidencia, y costaba una tarde entera volver a partir 577 fragmentos. Un
experimento de un minuto —subir el `topK`— mostró que los fragmentos que faltaban **sí existían**;
solo quedaban por debajo del corte. El diagnóstico había confundido *"no llegó"* con *"no existe"*.

**"Subir el `chunkSize` de 1000 a 2000."**
El estudio más completo sobre el tema ([Zhou et al., 2026](https://arxiv.org/abs/2602.16974))
concluye que el tamaño del fragmento *"correlaciona débilmente con la efectividad en corpus"*. El
tamaño no es la palanca — **dónde se corta, sí**.

**"Limitar `maxTokens` para controlar la latencia."**
`maxTokens` recorta la salida: trata el síntoma. Para los modelos de la familia GPT-5 el parámetro
que manda es `reasoning_effort`, porque *"responder con RAG no es una tarea de razonamiento"*
([Microsoft](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/gpt-5-will-it-rag/4442676)).
El modelo estaba razonando un problema que la búsqueda ya había resuelto.

El patrón: **los fallos que cuestan caro no son los que revientan.** Un parámetro mal puesto se
anuncia solo — el sistema falla y te lo dice. Un diagnóstico seguro de sí mismo, no: se lee bien,
suena terminado, y te manda a construir lo equivocado durante media tarde.

Los tres se atajaron igual: preguntando si eso estaba verificado o se estaba afirmando de memoria,
y corriendo el experimento barato antes de autorizar el caro.

---

## Límites conocidos

Van escritos porque un resultado sin sus límites no es un resultado.

- **Un solo documento, 577 fragmentos.** Pedir 20 es el 3.5% de este corpus; contra 100.000
  fragmentos sería el 0.02%. **El arreglo del `topK` no escala** — pasado cierto volumen la
  respuesta es reranking, no pedir más fragmentos.
- **20 preguntas.** La guía de los practicantes sitúa un golden dataset inicial en
  [50–100](https://qdrant.tech/blog/rag-evaluation-guide/).
- **El corpus tiene enmiendas hasta marzo de 2013.** Las multas civiles del § 160.404 se ajustan
  por inflación, así que el sistema responde cifras de 2013. Eso es un problema del corpus, no de
  la recuperación — y mantener los documentos al día es parte del servicio, no un extra.
- **Recuperación y generación se califican juntas.** La evaluación mide la respuesta final; no
  registra por separado si el fragmento correcto llegó a entrar en el contexto.

---

## Lo que sigue

1. **Parent-document retrieval** — las cuatro preguntas que siguen fallando tienen su respuesta
   completa dentro de una sola sección. Devolver la sección entera le gana a devolver veinte
   fragmentos sueltos, y arregla el problema de ruido que rompió la pregunta 16.
2. **Arreglar la pregunta 2 en el prompt** — que cite antes de resumir. Ni el chunking ni el
   `topK` tocan un fallo de generación.
3. **`reasoning_effort: low`** y un **timeout de 30–60 s** con aviso al usuario. El corte actual
   está en 604 s, que en un chat es lo mismo que no tener ninguno.

---

## Estructura del repositorio

```
docker-compose.yml           Postgres con pgvector y Ollama, sin puertos publicados
evaluacion/preguntas.md      Las 20 preguntas, las respuestas verificadas a mano y los resultados
evaluacion/investigacion-*   La investigación con fuentes detrás de las decisiones de chunking
```

Los secretos viven en un `.env` que no se versiona. La base de datos no publica ningún puerto.
