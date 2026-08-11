*[English](README.md) · **Español***

# RAG privado — medido, no demostrado

Un sistema de recuperación aumentada por generación que corre entero en mi propio servidor y
responde preguntas sobre normativa de salud de EE. UU. **sin que los documentos salgan nunca de la
máquina**.

Lo que este repo quiere mostrar no es que funciona. Es que **medí qué tan bien funciona, encontré
dónde se rompe, y puedo probar cuál de los arreglos valía la pena** — incluidos los que hice mal.

**Stack:** PostgreSQL 17 + pgvector · Ollama con BGE-M3 (local, solo CPU) · n8n · `gpt-5-mini`
**Servidor:** Hetzner CX33 — 4 vCPU, 8 GB de RAM, sin GPU · ~$9 al mes
**Corpus:** HIPAA, 45 CFR partes 160/162/164 — 148 secciones de la API del eCFR, vigentes al 6 ago 2026

---

## Resultados

20 preguntas con la respuesta verificada a mano contra la fuente. 16 tienen respuesta conocida;
**4 son de control y su respuesta correcta es que el sistema diga que no sabe.**

| | PDF, topK 5 | PDF, topK 20 | **Corpus por secciones** |
|---|---|---|---|
| Completas y correctas (de 16) | 7 | 11 | **12** |
| Fallos (de 16) | 9 | 5 | **4** |
| Falso negativo (se calló teniendo la respuesta) | 0 | **1** | **0** |
| Preguntas de control superadas | **4 / 4** | **4 / 4** | **4 / 4** |
| **Alucinaciones** | **0** | **0** | **0** |
| **Puntaje estricto** | 11/20 — 55% | 15/20 — 75% | **16/20 — 80%** |

**Ese +5 no es un resultado.** Con n=20 el puntaje carga ±18 puntos, y 75→80 es una sola pregunta.
Reportarlo como "mejoró a 80%" sería reportar ruido.

**El resultado es este:**

| Subir el `topK` de 5 a 20 | arregló 4 · **rompió 1** |
| Reestructurar el corpus | arregló 3, más recuperó una pregunta que antes daba timeout · **rompió 0** |

El primer cambio fue un canje. El segundo no. Y esa diferencia solo se ve porque las mismas 20
preguntas corrieron contra los dos.

**Y los cuatro fallos que quedan no son de recuperación.** Medido aparte, sin ningún LLM de por
medio: la búsqueda vectorial devuelve la sección esperada en **16 de 16** preguntas (MRR 0.865), y
en esas cuatro concretamente la deja en los puestos **1, 1, 2 y 1**. El recuperador ya está en su
techo — las cuatro fallan al redactar. La búsqueda híbrida se construyó para arreglarlas y empeoró
la recuperación; ver *Construido, medido, descartado*.

> **Esta tabla se midió sobre el corpus tal como estaba el 9 de agosto, y no se ha vuelto a correr.**
> El 10 de agosto el corpus se reconstruyó dos veces —ver *Un defecto que el puntaje no podía ver*—
> y los números de recuperación mejoraron. Volver a correr estas veinte preguntas cuesta tokens de
> OpenAI y un golden dataset lo bastante grande para que el resultado signifique algo, así que el
> puntaje de abajo se queda como se midió en vez de reescribirse en silencio.

---

## Qué responde de verdad

![Dos preguntas en una sesión: la primera devuelve seis casos con su cita, la segunda se niega porque el GDPR no está en el corpus](chat-example.png)

Dos preguntas, una sesión, nada montado.

**La primera** pregunta en español en qué casos no aplica el estándar de *minimum necessary*, contra
una norma en inglés. Vuelve con los seis casos y la cita — `45 CFR 164.502` — que es una sección que
cualquiera puede abrir y comprobar.

**La segunda** pregunta por la multa máxima del GDPR. El GDPR no está en este corpus. La respuesta
es la frase exacta de rechazo, y **esa es la mitad que compra una clínica**: un sistema que se calla
es auditable; uno que improvisa es un riesgo legal.

**El panel de la derecha es lo que vale leer dos veces.** Enseña lo que el texto solo puede afirmar:

| `Success in 17.729s` | Latencia real, en 4 vCPU sin GPU |
| `~5811 Tokens` | Lo que cuesta una respuesta |
| `20 items` entrando por la conexión Tool | Los 20 fragmentos que de verdad llegan al modelo |
| `1024 items` en Embeddings | La firma de BGE-M3 — calculados en la misma máquina que los guarda |
| El árbol de ejecución | Buscó **antes** de escribir. Esa es la regla 1 del prompt, cumplida |

---

## La forma

```
INDEXAR — se paga una vez, ~9 min en 4 vCPU sin GPU

  API del eCFR ──→ 148 archivos Markdown ──→ un POST por sección ──→ n8n
   3 llamadas          uno por §              webhook autenticado       │
                                                                        │
                                       partir 1000 / 150 de solape ─────┤
                                    embeddings BGE-M3, en local ────────┤
                                                                        ↓
                                                PostgreSQL + pgvector
                                                581 fragmentos, cada uno con el
                                                encabezado de su sección en el
                                                texto, más su §, su cita oficial
                                                y la fecha en que se descargó


PREGUNTAR — mediana 16 s

  pregunta en español ──→ BGE-M3 ──→ 20 fragmentos más cercanos ──→ gpt-5-mini
   contra texto inglés   mismo modelo      desde pgvector             redacta
                         que al indexar                                  │
                                                                         │
                            respuesta + cita verificable ────────────────┤
                     o "No encontré eso en los documentos cargados" ─────┘
```

**Nada cruza la frontera del medio.** El documento se convierte en vectores en la misma máquina que
los guarda; solo los 20 fragmentos recuperados salen del servidor.

---

## Cómo se corre

```bash
docker compose up -d                                  # Postgres + pgvector, Ollama
docker compose exec ollama ollama pull bge-m3         # modelo de embeddings, 1.2 GB

pwsh corpus/descargar-corpus.ps1                      # 3 llamadas a la API → 148 archivos .md
```

Se importan los dos workflows de [`workflows/`](workflows/) en n8n. Cada nodo lleva una nota que
explica qué hace y por qué, y todo campo que haya que cambiar está marcado con `>>> REPLACE`: tres
credenciales (Postgres, Ollama, header auth) y nada más.

```powershell
$env:RAG_N8N   = "https://tu-n8n.ejemplo.com"
$env:RAG_TOKEN = "<el token de header-auth que creaste>"
pwsh corpus/cargar-en-n8n.ps1                         # 148 POST, ~9 min en 4 vCPU
```

Ni Postgres ni Ollama publican puertos. El webhook de carga exige un token de cabecera.

---

## La decisión de arquitectura que importa

**Los embeddings corren en local. Solo los fragmentos recuperados salen del servidor.**

Ese es el argumento entero para una clínica o un laboratorio: el documento nunca se sube a ningún
lado. BGE-M3 lo convierte en vectores en la misma máquina que los guarda.

Una segunda decisión que no cuesta nada y evita una caída: **este stack tiene su propio archivo de
compose**, separado de la instancia de n8n donde corre el bot de un cliente. Bajar el RAG para
mantenimiento no puede dejar a un cliente sin servicio.

---

## El hallazgo que cambió el proyecto

La primera versión indexaba un **PDF**: 115 páginas, 577 fragmentos, cortados cada 1000 caracteres.
Siete de dieciséis respuestas salieron incompletas porque las listas numeradas quedaban partidas
entre fragmentos.

El diagnóstico obvio era "arreglar el chunking". **Era el diagnóstico equivocado.**

La norma la publica el eCFR con una **API pública sin llave**, y devuelve cada sección como un
`<DIV8 TYPE="SECTION">` con su número y su cita oficial como atributos. La estructura que iba a
reconstruir con un regex **estaba en la fuente desde el principio**.

```
3 llamadas a la API  →  148 archivos Markdown, uno por sección  →  581 fragmentos,
                        cada uno con su §, su cita oficial y su fecha de descarga
```

**El cuello de botella nunca fue la estrategia de chunking. Fue elegir mal el formato de entrada.**
Un PDF es una foto del documento; el XML es el documento.

De ahí cayeron dos cosas gratis:

- **La procedencia viaja con cada fragmento** — `section`, `citation`, la URL de `source` y la fecha
  `retrieved`. Eso es lo que hace una respuesta auditable en vez de solo creíble.
- **El corpus está al día.** El PDF tenía enmiendas hasta marzo de 2013. La API informa su propia
  fecha de vigencia, así que el corpus no puede envejecer en silencio.

### Y el corpus sí estaba viejo

El eCFR también expone un **endpoint de versiones**. Al consultarlo por las 17 secciones que
sostienen la evaluación devolvió **33 registros de enmienda, todos posteriores a la fecha del PDF**.
Tres secciones traen enmiendas de 2024 y 2026 — una de hace **poco más de dos meses**.

Verificado a mano: los montos del § 160.404 y los cinco elementos del § 164.404 están sin cambios,
así que esas respuestas siguen valiendo. **El punto no es que las respuestas estuvieran mal: es que
no había forma de saberlo sin comprobarlo**, y una llamada de dos minutos reemplazó una tarde de
re-verificación.

Para un cliente eso no es una nota al pie, es el servicio: **sus documentos también envejecen.**

---

## Un defecto que el puntaje no podía ver

Encontrado el 10 de agosto midiendo el costo por consulta, no buscándolo: muchos de los fragmentos
recuperados eran un encabezado de sección y nada más.

Contado contra la base de datos: **80 de 653 fragmentos eran una sola línea que empezaba por `##`.**
Tres son secciones `[Reserved]` que de verdad no tienen cuerpo. **Los otros 77 eran un defecto.**

La causa es una línea en blanco. El partidor corta primero por línea en blanco, y todos los archivos
de sección se ven así:

```
## § 164.512 Uses and disclosures for which…
                                              ← esta línea en blanco es el defecto
(a) A covered entity may use or disclose…
```

Cuando el bloque siguiente ya casi llena el fragmento de 1000 caracteres, el encabezado de unos 70
no cabe junto a él y queda solo. Por eso los cuerpos medían entre 985 y 997 caracteres: el partidor
llena hasta el tope y deja el título afuera.

**El arreglo es una línea** — quitar la línea en blanco antes de enviar cada sección. Verificado
antes de correrlo, no después: en las 148 secciones, el encabezado más el primer párrafo llega como
mucho a **984 caracteres** (mediana 242), así que siempre caben en un fragmento y el partidor nunca
tiene que separarlos.

Después una segunda versión, cambiando exactamente una cosa: los mismos fragmentos con **el
encabezado de la sección al inicio de cada uno**, para que un trozo que dice `(D) ABO blood type and
rh factor` siga diciendo a qué pertenece. Mismos cortes, vectorizados de nuevo — la guía es la única
variable.

| | v2 — como se midió el 9 ago | v3 — encabezado pegado | v4 — encabezado en todos |
|---|---|---|---|
| Fragmentos | 653 | **581** | 581 |
| Fragmentos que son solo encabezado | **80** | 3 | 3 |
| Recall@10 | 16/16 | 16/16 | 16/16 |
| MRR@10 | 0.865 | 0.938 | **0.969** |
| Preguntas resueltas en el puesto 1 | 12/16 | 14/16 | **15/16** |

**Lo que no se puede afirmar con esto.** El recall no se movió: ya estaba en el techo antes de
empezar. De v3 a v4 cambió de puesto exactamente **una** pregunta, y una pregunta no es un
resultado; una prueba pareada necesita al menos seis pares discordantes en la misma dirección para
bajar de p < 0,05. Al 6% de cambio observado, eso serían unas 96 preguntas, no 50.

**Lo que sí se cuenta en vez de muestrearse.** v4 cuesta **639 caracteres más por consulta, un
4,0%** — medido sobre el top-20 real de las dieciséis preguntas, no estimado a partir de una media.
Son unas 160 fichas de entrada de más. Aquí no va una cifra en dólares a propósito: los precios de
las API se mueven, y un número que envejece mal es peor que ningún número.

**v4 se midió y no se adopta. El agente corre v3.**

El argumento para adoptarlo era que un fragmento que se explica solo ayuda al modelo a redactar, y
ese argumento se cayó al mirarlo de cerca. Leyendo lo que el recuperador entrega de verdad, cada
fragmento ya llega así:

```json
{"pageContent": "...", "metadata": {"seccion": "164.502", "citation": "45 CFR 164.502", ...}}
```

**El modelo ya tenía el número de sección y la cita oficial, por los metadatos, antes de que v4
existiera.** Lo que el encabezado le añade al texto es el título descriptivo, y eso solo cambia el
vector, no lo que sabe el redactor. Así que v4 mejora la recuperación, en una pregunta, y nada más
que se pueda demostrar.

En contra: 4% más de fichas en cada consulta para siempre, un paso más de instalación, y un script
de 120 líneas que este repositorio tendría que cargar y mantener. **Una pregunta que no se distingue
del ruido no paga eso.** La tabla `documentos_v4` se queda en el servidor —borrar un experimento
medido sería esconder el resultado— pero no está en la tubería y su script no está en este repo.

Es el mismo veredicto que la búsqueda híbrida, y por el mismo camino: construido, medido, no
adoptado.

**La parte incómoda:** nada de esto se veía en el 16/20. Un puntaje cuenta respuestas buenas y
malas; no puede ver 77 fragmentos vacíos ocupando puestos, ni un encabezado colocado por encima del
texto al que pertenece. **Hizo falta medir el costo —una métrica que no tiene nada que ver con la
calidad— para encontrar un defecto de calidad.**

---

## Lo que encontró la evaluación

**Cero alucinaciones en 20 preguntas, en las tres rondas.** Las cuatro de control respondieron *"No
encontré eso en los documentos cargados"* todas las veces.

**Subir `topK` de 5 a 20 arregló cuatro respuestas y rompió una.** La pregunta 16 pasó de
parcialmente correcta a *"No encontré eso"* — con veinte fragmentos en el contexto, la señal quedó
enterrada.

Ese resultado tiene un nombre que encontré después: **"Lost in the Middle"**. Las guías de
producción lo dicen sin rodeos: *no devuelvas más de 10 documentos sin reranking, o el modelo ignora
lo que queda en el medio del contexto*. Subir el `topK` compró recall y lo pagó con precisión.

**Un error que ningún lector habría detectado.** A la pregunta de a partir de cuántos afectados hay
que avisar a los medios, el sistema respondió *"a partir de 500"* mientras citaba el texto que él
mismo había recuperado: *"more than 500 residents"*. Una brecha que afecte exactamente a 500
personas **no** obliga a avisar a los medios. *(Corregido en el corpus por secciones.)*

**Los fallos de recuperación y los de generación se arreglan al revés** — y ahora se pueden
distinguir, leyendo qué devolvió de verdad el paso de recuperación.

**Dos de los cuatro fallos que quedan son citas equivocadas**, y no son fallos nuevos: son fallos
que antes eran invisibles. Una cita que apunta a un documento de 115 páginas nunca puede estar mal.
Una que apunta a `45 CFR 164.530` sí, y lo está: las salvaguardas de la Security Rule viven en los
§§ 164.308, 164.310 y 164.312.

**Los otros dos son dilución de ranking, y se midió.** Preguntado por la definición de *business
associate*, el sistema devolvió una respuesta a la que le faltaba la cláusula central. Leyendo el
paso de recuperación se ve por qué: **solo 3 de los 20 fragmentos venían del § 160.103**, la sección
que define el término. Los otros 17 salieron de siete secciones que **mencionan** business
associates sin **definirlos**.

El término aparece por toda la norma, así que la búsqueda por significado trajo el tema entero y le
dejó tres puestos de veinte a la única sección que contesta. **Ese es el caso de libro para búsqueda
híbrida y reranking.**

> **Medido el 9 ago, y aquí el libro se equivocó.** La búsqueda híbrida sacó al § 160.103 del top 10
> por completo; la vectorial pura lo tiene de **primero**. La dilución es real —3 puestos de 20— pero
> el arreglo que se propuso para ella, no. Ver *Construido, medido, descartado*.

**Dos hipótesis murieron a mitad de ronda.** La primera: *"las preguntas de lista fallan y las de
dato puntual aciertan"* — la mató la P12, cuatro niveles de multas respondidos enteros. La segunda:
*"falla cuando la sección es enorme"* — la mató la P16, perfecta sobre una de las secciones más
grandes. La tercera hipótesis, dilución por popularidad del término, encaja con los veinte casos y
**queda escrita como hipótesis**, a probar con el reranking en vez de anunciarse como conclusión.

**Y el aviso metodológico que pesa más que el puntaje.** La pregunta 14 se corrió dos veces con una
configuración idéntica. La primera devolvió los cinco elementos exigidos **más uno del § 164.410**.
La segunda devolvió los cinco limpios. Nada cambió entre las dos. **El modelo no es determinista**,
así que este 80% carga dos ruidos: el de la muestra y el del propio modelo.

---

## Método: medir antes de construir

Durante este proyecto se propusieron cuatro arreglos caros. **Tres estaban equivocados, y medir es
lo que lo demostró.**

**"Los fragmentos están cortados a mitad de lista — hay que reindexar con otra estrategia."**
Sonaba bien, venía con evidencia, y costaba una tarde entera. Un experimento de un minuto —subir el
`topK`— mostró que los fragmentos que faltaban **sí existían**; solo quedaban por debajo del corte.
El diagnóstico había confundido *"no llegó"* con *"no existe"*.

**"Subir el `chunkSize` de 1000 a 2000."**
El estudio más completo sobre el tema ([Zhou et al., 2026](https://arxiv.org/abs/2602.16974))
concluye que el tamaño del fragmento *"correlaciona débilmente con la efectividad en corpus"*. El
tamaño no es la palanca — **dónde se corta, sí**.

**"Limitar `maxTokens` para controlar la latencia."**
`maxTokens` recorta la salida: trata el síntoma. Para los modelos de la familia GPT-5 el parámetro
que manda es `reasoning_effort` — un ingeniero que corrió
[la evaluación de RAG de Microsoft](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/gpt-5-will-it-rag/4442676)
observó que con `minimal` el modelo nunca gastó tokens de razonamiento y aun así dio respuestas de
calidad, y plantea que responder con RAG quizá no sea una tarea de razonamiento. **Él mismo dice que
no probó la alternativa**, así que es una pista, no un hallazgo — que es exactamente como se debió
citar la primera vez. *(Ver la [auditoría de fuentes](evaluacion/investigacion-chunking.md#source-audit--what-survived-verification-and-what-didnt).)*

**"Escribir un preprocesador que extraiga el § de cada fragmento."**
Dos horas de parseo que sobraron por una pregunta que nadie había hecho: *¿de dónde salió este PDF?*

El patrón: **los fallos que cuestan caro no son los que revientan.** Un parámetro mal puesto se
anuncia solo. Un diagnóstico seguro de sí mismo, no: se lee bien, suena terminado, y te manda a
construir lo equivocado durante media tarde.

### Quién los propuso

Los cuatro arreglos los propuso el asistente de IA con el que se construyó esto, en Claude Code.
Tres estaban mal — y **ninguno lo detectó el propio asistente revisando su trabajo.** Los cuatro
los atajó la misma pregunta humana: *¿esto está verificado o lo estás afirmando de memoria?*

Esa pregunta es el método. La herramienta es reemplazable; el hábito de exigir evidencia antes de
autorizar media tarde de trabajo, no.

---

## Límites conocidos

Van escritos porque un resultado sin sus límites no es un resultado.

- **20 preguntas, así que el puntaje absoluto carga ±18 puntos.** Ninguna guía que encontré pone el
  piso por debajo de 50: [QASkills](https://qaskills.sh/blog/golden-dataset-llm-evaluation-guide)
  dice 50–100 como mínimo viable, [Braintrust](https://www.braintrust.dev/articles/what-is-rag-evaluation)
  50–200, y [Microsoft](https://medium.com/data-science-at-microsoft/the-path-to-a-golden-dataset-or-how-to-evaluate-your-rag-045e23d1f13f)
  *"certainly not less than 100"*. Ni siquiera 50 baja el margen de ±12. La comparación pareada es
  el resultado; el porcentaje es un orden de magnitud.
- **Una sola ejecución por pregunta.** La P14 demostró que el modelo da respuestas distintas ante
  entradas idénticas.
- **581 fragmentos.** Pedir 20 es el 3% de este corpus; contra 100.000 sería el 0.02%. **El arreglo
  del `topK` no escala.**
- **Solo búsqueda vectorial, sin híbrida — y ahora eso es una decisión, no una carencia.** Los
  embeddings encuentran por significado, no por cadena exacta. En la medición de Anthropic, sumar
  BM25 bajó el fallo de recuperación de 3.7% a 2.9%; esta máquina no puede correr BM25, y la versión
  con `ts_rank_cd` se midió aquí y **empeoró** la recuperación. Ver *Construido, medido, descartado*.
- **La tabla no tiene índice vectorial** — solo la clave primaria. Cada búsqueda recorre los 581
  fragmentos uno por uno.
- ~~**Dos de los veinte puestos recuperados eran encabezados de sección** — una línea cada uno. Un
  10% del contexto desperdiciado.~~ **Arreglado el 10 ago.** Eran 77 fragmentos defectuosos de 653,
  y sobre las dieciséis preguntas ocupaban 16 de 160 puestos. Ahora cero. Ver *Un defecto que el
  puntaje no podía ver*.
- **El § 160.404 remite a la parte 102 del 45 CFR para los montos ajustados por inflación, y la
  parte 102 no está en el corpus.** La norma se referencia fuera de sus propias partes.

---

## Construido, medido, descartado: la búsqueda híbrida

La búsqueda híbrida era el primer punto de esta lista. Se construyó, se midió contra el golden
dataset, y **empeoró el sistema.** No está conectada al agente.

|  | Recall@10 | MRR |
|---|---|---|
| **Vectorial pura** | **16/16** | **0.865** |
| Híbrida, RRF, 0.3 vectorial / 0.7 léxica | 13/16 | 0.435 |

Ocho de dieciséis preguntas quedaron peor, una mejor, y tres se cayeron del top 10 por completo.
Método y tabla pregunta por pregunta: [`evaluacion/preguntas.md`](evaluacion/preguntas.md), ronda 4.
La consulta, con el veredicto arriba del todo: [`sql/busqueda-hibrida.sql`](sql/busqueda-hibrida.sql).

**Por qué falló aquí, y qué queda sin demostrar de esa explicación.** Los documentos están en inglés
y las preguntas en español. La búsqueda por texto no cruza idiomas, así que la mitad léxica aporta
ruido en vez de señal. La advertencia estaba escrita en este mismo README antes de que existiera la
medición, y la medición la convirtió de nota al pie en titular.

**Pero esta configuración cambia tres cosas a la vez** frente a la búsqueda vectorial pura, y la
medición no las puede separar:

| Factor | En esta corrida | Por qué podría ser el culpable él solo |
|---|---|---|
| Corpus con dos idiomas | Documentos en inglés, preguntas en español | La mitad léxica no tiene con qué emparejar |
| Reparto del peso | **70% léxico**, 30% vectorial | Se le dio la mayoría del voto a la mitad más débil |
| Motor léxico | `ts_rank_cd`, no BM25 | Premia la repetición y no sabe nada de las estadísticas del corpus |

**Así que "la búsqueda híbrida empeoró esto" es exacto; "la búsqueda híbrida empeora las cosas" no
lo es.** La recuperación híbrida es una familia de configuraciones y aquí se midió una sola.
Aislar los tres factores serían tres corridas, una por factor, contra la misma referencia fija.
Hasta que eso se corra, la explicación del idioma es la hipótesis principal, no una causa demostrada.

> **Y ahora hay un cuarto factor, encontrado después.** Esto se midió sobre el corpus v2, donde 77
> fragmentos eran solo un encabezado de sección. **Un encabezado suelto contiene el número de sección
> como cadena literal, que es justo lo que mejor encuentra la búsqueda por texto** — así que parte de
> lo que la mitad léxica estaba ordenando eran fragmentos vacíos. Eso no rescata el resultado:
> significa que la corrida tiene un factor confundido más de los que admite la tabla de arriba, y que
> las corridas de aislamiento van sobre el corpus limpio. La referencia fija para ellas es
> **vectorial pura en 16/16 y MRR 0,938** sobre v3.

**Lo que la misma medición dijo de los cuatro fallos abiertos.** Las preguntas 6, 7, 8 y 15 fallaron
en la ronda 3. Sus puestos en vectorial pura son **1, 1, 2 y 1** — la sección correcta ya llegaba
arriba. Son fallos de redacción, no de recuperación. **Ningún trabajo sobre el recuperador los
habría movido**, y la versión anterior de esta sección proponía exactamente eso.

**Dos predicciones que hizo este README, las dos falsas.** Decía que la híbrida *"encontraría el
`160.103` como cadena exacta"*: la híbrida lo sacó del top 10 mientras la vectorial lo tiene de
primero. Y decía *"si repara 2 o 3 de las 20, funcionó"*: no reparó ninguna y rompió ocho. Las dos
frases se quedan arriba, sin corregir, porque una predicción borrada después del hecho no enseña
nada.

La consulta se queda en el repositorio. Es correcta, está documentada, y un corpus en un solo idioma
probablemente sí se beneficiaría. **El hallazgo es que una técnica recomendada, medida, puede ser un
retroceso** — y que la búsqueda vectorial con un modelo de embeddings multilingüe ya estaba en el
techo para este corpus.

---

## Lo que sigue

1. **Volver a correr las veinte preguntas sobre v3.** Todos los números de recuperación mejoraron y
   el puntaje no se ha vuelto a medir, así que ahora mismo la tabla de resultados describe un corpus
   que el sistema ya no usa.

2. **Un golden dataset más difícil, no solo más grande.** El recall está en 16/16, así que añadir
   cincuenta preguntas de la misma dificultad añade cincuenta preguntas que nadie falla y no compra
   ni un gramo de poder estadístico. Lo que compra poder son preguntas que el sistema pueda perder:
   respuestas repartidas en dos o tres secciones, palabras que no aparecen en el texto, casos
   negativos y excepciones, y secciones que se parecen entre sí. Cada una necesita su respuesta
   verificada escrita, no solo su número de sección — si no, mide si encontró la página, no si la
   leyó bien.

3. **Arreglar en el prompt los dos fallos de cita.** Ni el chunking ni el `topK` tocan un fallo de
   generación — y la medición de arriba dice que la generación es donde viven los fallos que quedan.

2. **Reranking, y no en esta máquina.** `bge-reranker-v2-m3` atacaría los dos tipos de fallo a la
   vez, pero **Ollama no puede servir modelos de reranking.** Verificado el 9 ago: un mantenedor de
   Ollama lo dice sin rodeos en el [issue #10467](https://github.com/ollama/ollama/issues/10467),
   cerrado como duplicado del [#3368](https://github.com/ollama/ollama/issues/3368), la petición de
   esa función abierta desde marzo de 2024. La trampa que hay que nombrar: **sí** se puede descargar
   un reranker en Ollama y llamarlo por `/api/embed`, y devuelve números — la capa de embeddings, no
   la cabeza de clasificación que hace el ranking. **Salida plausible, silenciosamente equivocada.**
   El único nodo de reranking de n8n es Cohere, que sacaría los fragmentos de la máquina y rompería
   la única promesa que hace este proyecto. Así que esto se prueba en una máquina con GPU, que además
   es el número que de verdad obtendría un cliente con GPU.

   **Corrección del 9 ago:** esta sección decía que el reranker *"corre en el mismo Ollama"*. No
   corre. Esa línea se escribió por suposición, no por verificación.

---

## Estructura del repositorio

```
docker-compose.yml              Postgres con pgvector y Ollama, sin puertos publicados
corpus/descargar-corpus.ps1     Baja 45 CFR 160/162/164 de la API del eCFR → un .md por sección
corpus/cargar-en-n8n.ps1        Manda cada sección a un webhook autenticado de n8n para indexarla.
                                También pega cada encabezado a su primer párrafo — una línea, y el
                                porqué está en el comentario de encima
workflows/cargar-secciones.json El workflow de indexación. Se importa en n8n.
workflows/preguntar.json        El workflow de consulta: agente, recuperador y embeddings locales.
workflows/system-prompt.md      Las cinco reglas del prompt, y qué se midió que hace cada una
sql/busqueda-hibrida.sql        La recuperación híbrida en una sentencia — medida, peor, y guardada
                                porque el hallazgo es ese. El veredicto va arriba del archivo.
evaluacion/preguntas.md         Las 20 preguntas, las respuestas verificadas a mano y las cuatro rondas
evaluacion/medir-recuperacion.py  Puntúa solo la recuperación, sin LLM: vectorial vs híbrida, recall@10 y MRR
evaluacion/investigacion-*      La investigación con fuentes detrás de las decisiones
```

Los dos archivos de workflow no llevan credenciales — solo los campos que hay que rellenar, marcados
con `>>> REPLACE`. Los nombres de los nodos están en español porque soy yo quien los lee a las 3 de
la mañana cuando algo se para.

**`system-prompt.md` vale abrirlo aunque nunca corras esto.** Son cinco reglas, y lo que importa es
la medición pegada a cada una: cuál produjo cero alucinaciones en sesenta respuestas, cuál no hizo
nada durante dos rondas, y **cuál falló a la vista**.

El corpus no se versiona: `descargar-corpus.ps1` lo regenera en unos diez segundos, y estaría
desactualizado desde el momento en que se subiera.

**Los documentos de la evaluación están en español a propósito.** Las preguntas se hacen en español
contra una norma en inglés; ese cruce es parte de lo que se mide, así que traducirlas borraría el
experimento.

Los secretos viven en un `.env` que no se versiona.
