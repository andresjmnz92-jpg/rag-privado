*[English](README.md) · **Español***

# RAG privado — medido, no demostrado

Un sistema de recuperación aumentada por generación que corre entero en mi propio servidor, hecho
para responder preguntas sobre documentos normativos **sin que los documentos salgan nunca de la
máquina**.

Lo que este repo quiere mostrar no es que funciona. Es que **medí qué tan bien funciona, encontré
dónde se rompe, y puedo probar cuál de los arreglos valía la pena** — incluido el que hice mal.

**Stack:** PostgreSQL 17 + pgvector · Ollama con BGE-M3 (local, solo CPU) · n8n ·
`gpt-5-mini` para redactar
**Servidor:** Hetzner CX33 — 4 vCPU, 8 GB de RAM, sin GPU · ~$9 al mes
**Corpus:** HIPAA Administrative Simplification, 45 CFR partes 160, 162 y 164 — 148 secciones,
bajadas de la API del eCFR, vigentes al 6 de agosto de 2026

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

## El hallazgo que cambió el proyecto

La primera versión indexaba un **PDF**: 115 páginas, 577 fragmentos, cortados cada 1000
caracteres. Siete de dieciséis respuestas salieron incompletas porque las listas numeradas quedaban
partidas entre fragmentos.

El diagnóstico obvio era "arreglar el chunking". **Era el diagnóstico equivocado.**

La norma la publica el eCFR con una **API pública sin llave**, y devuelve cada sección como un
`<DIV8 TYPE="SECTION">` con su número y su cita oficial como atributos. La estructura que iba a
reconstruir con un regex **estaba en la fuente desde el principio**.

```
3 llamadas a la API  →  148 archivos Markdown, uno por sección  →  653 fragmentos,
                        cada uno con su §, su cita oficial y su fecha de descarga
```

**El cuello de botella nunca fue la estrategia de chunking. Fue elegir mal el formato de entrada.**
Un PDF es una foto del documento; el XML es el documento. Cada hora ajustando el tamaño del
fragmento se fue en reconstruir una estructura que un `curl` entregaba intacta.

De ahí cayeron dos cosas gratis:

- **La procedencia viaja con cada fragmento.** Cada uno lleva `section`, `citation`, la URL de
  `source` y la fecha `retrieved`. Eso es lo que hace una respuesta auditable en vez de solo
  creíble.
- **El corpus está al día.** El PDF tenía enmiendas hasta marzo de 2013. La API informa su propia
  fecha de vigencia, así que el corpus no puede envejecer en silencio.

### Y el corpus sí estaba viejo

El eCFR también expone un **endpoint de versiones**. Al consultarlo por las 17 secciones que
sostienen la evaluación devolvió **33 registros de enmienda, todos posteriores a la fecha del PDF**.

La mayoría se agrupan en una sola fecha de 2016 y parecen una enmienda técnica. Tres no:
`160.103`, `164.502` y `164.520` traen enmiendas de 2024 y 2026 — una de ellas de hace **poco más
de dos meses**.

Verificado a mano: los montos de las multas del § 160.404 y los cinco elementos de notificación del
§ 164.404 están sin cambios, así que esas respuestas siguen valiendo. **El punto no es que las
respuestas estuvieran mal. Es que no había forma de saberlo sin comprobarlo** — y una llamada de
dos minutos reemplazó una tarde de re-verificación.

Para un cliente eso no es una nota al pie, es el servicio: **sus documentos también envejecen.**

---

## Resultados

20 preguntas con la respuesta verificada a mano contra la fuente — 16 con respuesta conocida, y
**4 preguntas de control cuya respuesta correcta es que el sistema diga que no sabe**.

| | PDF, topK 5 | PDF, topK 20 | **Corpus por secciones** |
|---|---|---|---|
| Completas y correctas (de 16) | 7 | 11 | **12** |
| Fallos (de 16) | 9 | 5 | **4** |
| Falso negativo (se calló teniendo la respuesta) | 0 | **1** | **0** |
| Preguntas de control superadas | **4 / 4** | **4 / 4** | **4 / 4** |
| **Alucinaciones** | **0** | **0** | **0** |
| **Puntaje estricto** | 11/20 — 55% | 15/20 — 75% | **16/20 — 80%** |

**Ese +5 no es un resultado.** Con n=20 el puntaje carga ±18 puntos, y 75→80 es **una sola
pregunta**. Quien lo reporte como "mejoró a 80%" está reportando ruido.

**Y la tercera columna se calificó con una vara más dura que las otras dos.** Esta ronda añadió
*"una cita equivocada cuenta como fallo"* — una regla que antes ni siquiera era aplicable, porque
en el corpus en PDF todas las respuestas citaban el nombre del documento entero. Con la vara vieja
esta ronda da **18/20 — 90%**. Los dos números están en el archivo de evaluación; mover la vara en
silencio habría sido la opción deshonesta.

### Lo que el número no dice, y la comparación sí

**Nada de lo que funcionaba dejó de funcionar.**

| Subir el `topK` de 5 a 20 | arregló 4 · **rompió 1** |
| Reestructurar el corpus | arregló 3, más recuperó la P14 que antes daba timeout · **rompió 0** |

El cambio del `topK` fue un canje. Este no. **Ese es el hallazgo, no el porcentaje.**

**Latencia**, sobre 23 ejecuciones del corpus en PDF: mediana 16 s · peor caso completado 262 s ·
un timeout a los 604 s. En el corpus por secciones, la pregunta 1 respondió en 14 s y la 14 —que
antes nunca terminaba— en 29 s.

**Indexación:** 653 fragmentos en unos 9 minutos, en 4 vCPU sin GPU. Se paga una sola vez.

---

## Lo que encontró la evaluación

**Cero alucinaciones en 20 preguntas.** Las cuatro de control se respondieron con *"No encontré eso
en los documentos cargados"* — incluida una trampa que preguntaba el precio de la certificación
oficial de HIPAA, que no existe. Para un comprador del sector salud ese es el número que importa:
un sistema que se calla es auditable; uno que improvisa es un riesgo legal.

**Subir `topK` de 5 a 20 arregló cuatro respuestas y rompió una.** La pregunta 16 pasó de
parcialmente correcta a *"No encontré eso"* — con veinte fragmentos en el contexto, la señal quedó
enterrada en ruido.

Ese resultado tiene un nombre que encontré después: **"Lost in the Middle"**. Las guías de
producción lo dicen sin rodeos: *no devuelvas más de 10 documentos sin reranking, o el modelo
ignora lo que queda en el medio del contexto*. Subir el `topK` compró recall y lo pagó con
precisión. **No fue un arreglo: fue un canje.**

**Un error que ningún lector habría detectado.** A la pregunta de a partir de cuántos afectados hay
que avisar a los medios, el sistema respondió *"a partir de 500"* mientras citaba el texto que él
mismo había recuperado: *"more than 500 residents"*. Una brecha que afecte exactamente a 500
personas **no** obliga a avisar a los medios. La recuperación fue correcta; el resumen, no.

**Los fallos de recuperación y los de generación se arreglan al revés.** La pregunta 14 falló
porque los fragmentos con la respuesta nunca llegaron al modelo. La 2 falló con el texto correcto
delante. El chunking arregla la primera; el prompt arregla la segunda. Mirando solo la respuesta
final, las dos se ven igual de "incompletas".

**Y ahora se pueden distinguir.** Leyendo el paso de recuperación de una sola ejecución sobre el
corpus reestructurado, la pregunta 14 recuperó los elementos (A)–(D) en el puesto 1 y el (E) en el
15 — pero la respuesta también incluyó un requisito del **§ 164.410**, que es otra obligación y de
otra parte. La recuperación hizo su trabajo; el redactor mezcló dos secciones.

**Ese error antes era invisible.** En el corpus en PDF todos los fragmentos citaban el mismo título
de documento. Ahora la cita lo delata a mitad de frase. **Los metadatos no arreglaron el fallo: lo
hicieron medible.**

**Dos de los cuatro fallos que quedan son citas equivocadas** — y no son fallos nuevos, son fallos
que antes eran invisibles. Una cita que apunta a un documento de 115 páginas nunca puede estar mal.
Una que apunta a `45 CFR 164.530` sí puede, y lo está: las salvaguardas de la Security Rule viven
en los §§ 164.308, 164.310 y 164.312.

**Los otros dos son dilución de ranking, y se midió.** Preguntado por la definición de *business
associate*, el sistema devolvió una respuesta a la que le faltaba la cláusula central. Leyendo el
paso de recuperación se ve por qué: **solo 3 de los 20 fragmentos recuperados venían del
§ 160.103**, la sección que define el término. Los otros 17 salieron de § 164.504, § 164.502,
§ 164.410, § 164.314, § 160.310, § 160.402 y § 162.923 — todos **mencionan** business associates,
ninguno los **define**.

El término aparece por toda la norma, así que la búsqueda por significado trajo el tema entero y
le dejó tres puestos de veinte a la única sección que contesta. **Ese es el caso de libro para
búsqueda híbrida y reranking**, las dos cosas que están en "lo que sigue".

**Dos hipótesis murieron a mitad de ronda.** La primera: *"las preguntas de lista fallan y las de
dato puntual aciertan"* — la mató la P12, una tabla de cuatro niveles de multas respondida entera.
La segunda: *"falla cuando la sección es enorme"* — la mató la P16, perfecta sobre una de las
secciones más grandes. La tercera hipótesis, dilución por popularidad del término, encaja con los
veinte casos y **queda escrita como hipótesis**, a probar con el reranking, no anunciada como
conclusión.

**Y el aviso metodológico que pesa más que el puntaje.** La pregunta 14 se corrió dos veces con
una configuración idéntica. La primera devolvió los cinco elementos exigidos **más uno del
§ 164.410**, que es otra obligación y de otra parte. La segunda devolvió los cinco limpios. Nada
cambió entre las dos. **El modelo no es determinista**, así que este 80% carga dos ruidos: el de
la muestra y el del propio modelo. Una evaluación rigurosa correría cada pregunta varias veces y
promediaría.

---

## Método: medir antes de construir

Durante este proyecto se propusieron cuatro arreglos caros. **Tres estaban equivocados, y medir es
lo que lo demostró.**

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

**"Escribir un preprocesador que extraiga el § de cada fragmento."**
Dos horas de parseo que sobraron por una pregunta que nadie había hecho: *¿de dónde salió este
PDF?* La fuente publica el mismo texto con la estructura ya puesta.

El patrón: **los fallos que cuestan caro no son los que revientan.** Un parámetro mal puesto se
anuncia solo — el sistema falla y te lo dice. Un diagnóstico seguro de sí mismo, no: se lee bien,
suena terminado, y te manda a construir lo equivocado durante media tarde.

Los cuatro se atajaron igual: preguntando si eso estaba verificado o se estaba afirmando de
memoria, y corriendo el experimento barato antes de autorizar el caro.

---

## Límites conocidos

Van escritos porque un resultado sin sus límites no es un resultado.

- **20 preguntas, así que el puntaje absoluto carga ±19 puntos.** La guía de los practicantes
  sitúa un golden dataset inicial en [50–100](https://qdrant.tech/blog/rag-evaluation-guide/) — y
  ni siquiera 50 lo baja de ±12. La comparación pareada es el resultado; el porcentaje es un orden
  de magnitud.
- **653 fragmentos.** Pedir 20 es el 3% de este corpus; contra 100.000 sería el 0.02%. **El arreglo
  del `topK` no escala** — pasado cierto volumen la respuesta es reranking.
- **Solo búsqueda vectorial, sin híbrida.** Los embeddings encuentran por significado, no por
  cadena exacta: son débiles buscando un `164.404` literal. La búsqueda por palabras clave (BM25)
  no lo es, y los sistemas de producción corren las dos. En la medición de Anthropic, sumar BM25
  bajó el fallo de recuperación de 3.7% a 2.9%.
- **La tabla no tiene índice vectorial** — solo la clave primaria. Cada búsqueda recorre los 653
  fragmentos uno por uno. Con este corpus no se nota; con cien mil, sí.
- **Dos de los veinte puestos recuperados eran encabezados de sección** — una línea cada uno, sin
  aportar nada. Un 10% del contexto desperdiciado.
- **El § 160.404 remite a la parte 102 del 45 CFR para los montos ajustados por inflación, y la
  parte 102 no está en el corpus.** La norma se referencia fuera de sus propias partes; responder
  del todo una pregunta sobre multas exigiría cargarla.

---

## Lo que sigue

1. **Reranking** — el único cambio que ataca los dos fallos abiertos a la vez: el ruido que rompió
   la pregunta 16 y el fragmento del § 164.410 que llegó al puesto 2. `bge-reranker-v2-m3` corre en
   el mismo Ollama. El costo es latencia, en CPU sin GPU, y **ninguna fuente que encontré da una
   cifra medida de cuánto** — así que se mide aquí.
2. **Búsqueda híbrida (BM25 + vectorial)** con Reciprocal Rank Fusion. Un índice GIN sobre
   `tsvector` al lado del vectorial — sin infraestructura nueva.
3. **Arreglar la pregunta 2 en el prompt** — que cite antes de resumir. Ni el chunking ni el `topK`
   tocan un fallo de generación.

---

## Estructura del repositorio

```
docker-compose.yml              Postgres con pgvector y Ollama, sin puertos publicados
corpus/descargar-corpus.ps1     Baja 45 CFR 160/162/164 de la API del eCFR → un .md por sección
corpus/cargar-en-n8n.ps1        Manda cada sección a un webhook autenticado de n8n para indexarla
evaluacion/preguntas.md         Las 20 preguntas, las respuestas verificadas a mano y los resultados
evaluacion/investigacion-*      La investigación con fuentes detrás de las decisiones
```

El corpus no se versiona: `descargar-corpus.ps1` lo regenera en unos diez segundos, y estaría
desactualizado desde el momento en que se subiera.

**Los documentos de la evaluación están en español a propósito.** Las preguntas se hacen en español
contra una norma en inglés: ese cruce de idiomas es parte de lo que se mide, así que traducirlas
borraría el experimento.

Los secretos viven en un `.env` que no se versiona. La base de datos no publica ningún puerto. El
webhook de carga exige un token de cabecera.
