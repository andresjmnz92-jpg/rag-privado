# Cómo resuelven esto los que lo hacen en producción

*Investigación del 8 de agosto de 2026 · 14 fuentes · Confianza: alta en las cifras de Anthropic
y el paper de taxonomía; media en las cifras de corpus legales (una sola fuente)*

## Resumen

La respuesta corta a la pregunta que originó esto: **subir el `chunkSize` es el parche.** La
evidencia dice que el tamaño del fragmento importa poco comparado con **dónde se corta**. Para un
documento como HIPAA —numerado, jerárquico, con listas explícitas— la corrección que usan los
equipos serios es **cortar por la estructura del propio documento y recuperar el padre completo**,
no agrandar la ventana.

Y hay un ajuste de un solo campo que se puede probar **hoy, sin reindexar nada**: subir `topK`
de 5 a 20.

---

## 1. El tamaño del fragmento no es la variable que manda

El hallazgo más directo contra "súbelo a 2000" viene del estudio más completo publicado sobre el
tema, que compara segmentación por estructura, semántica y guiada por LLM
([Zhou, Wang, Koopman & Zuccon, 2026](https://arxiv.org/abs/2602.16974)):

> *"Chunk size correlates **moderately** with in-document but **weakly** with in-corpus
> effectiveness"* — el método de segmentación importa más allá de las dimensiones del fragmento.

Y sobre qué método gana:

> *"Simple structure-based methods **outperform LLM-guided alternatives** for in-corpus retrieval."*

Traducido: cortar por los títulos y secciones del documento le gana a métodos mucho más caros y
sofisticados. No hace falta un LLM decidiendo dónde cortar — hace falta respetar la estructura que
el autor ya puso.

**El consenso de los practicantes coincide** ([Unstructured](https://unstructured.io/blog/chunking-for-rag-best-practices),
[Towards Data Science](https://towardsdatascience.com/rag-101-chunking-strategies-fdc6f6c2aaec/)):

> *"Los documentos reales ya tienen fronteras semánticas —encabezados, secciones, elementos de
> lista— y cortar por ellas le gana a cualquier ventana fija, porque el autor ya agrupó las ideas
> relacionadas."*

> *"La mayoría de los fallos de RAG son fallos de recuperación, y la mayoría de los fallos de
> recuperación empiezan en el chunking."*

**Aplicado a nuestro caso:** el § 164.404(c) tiene sus cinco elementos (A)–(E) escritos como una
unidad. Cortar cada 1000 caracteres los partió; cortar cada 2000 podría partirlos igual, solo que
en otro sitio. El problema no es la longitud de la tijera, es dónde se apoya.

---

## 2. Lo que se usa de verdad para textos legales: parent-document retrieval

Es la técnica que más aparece cuando la búsqueda se restringe a documentos legales y de
referencia.

**Cómo funciona** ([ZeroEntropy](https://zeroentropy.dev/concepts/parent-document-retrieval/)):
se indexan fragmentos **pequeños** (50–200 tokens) para que la búsqueda sea precisa, pero al
LLM se le entrega el fragmento **padre** completo (500–1500 tokens o la sección entera). Separa la
unidad de búsqueda de la unidad de lectura.

> *"Para prosa larga, documentación técnica y texto legal, parent-document retrieval es **casi
> siempre una ganancia neta**."*

**Por qué resuelve exactamente nuestro fallo** ([Edtek](https://edtek.ai/kb/chunking-strategies-legal-reference-documents/)),
que describe nuestro problema casi con las mismas palabras:

> *"La subsección (a)(2)(iv) de un estatuto define un término usado en la subsección (a)(2)(v). El
> chunking fijo las va a partir a mitad de definición."*

Su receta para documentos jerárquicos: **partir primero por los marcadores estructurales del
documento** —encabezados, saltos de sección, fronteras de párrafo— y luego recuperar el padre.

**El dato medido**, de un corpus de contratos: usar chunking por sección en vez de tamaño fijo da
**entre 8 y 15 puntos de mejora en recall@k**. *(Una sola fuente, sin paper detrás — tratar como
orden de magnitud, no como cifra exacta.)*

**Lo que cuesta:** casi nada. El índice pesa lo mismo porque solo se embeben los hijos; recuperar
el padre es una consulta por ID. No hay coste extra de embeddings ni de LLM.

---

## 3. Contextual Retrieval (Anthropic): más caro, mejor medido

Es la técnica con los números más sólidos, porque los publicó quien la inventó
([Anthropic Engineering](https://www.anthropic.com/engineering/contextual-retrieval)). Consiste en
que un LLM escriba 50–100 tokens de contexto para **cada fragmento** antes de indexarlo.

Tasa de fallo de recuperación (1 − recall@20):

| Configuración | Fallo | Mejora |
|---|---|---|
| Embeddings base | 5.7% | — |
| + Contextual Embeddings | 3.7% | −35% |
| + Contextual BM25 | 2.9% | −49% |
| + Reranking | **1.9%** | **−67%** |

**Coste:** *"$1.02 por millón de tokens de documento"*, una sola vez, con prompt caching. Para
nuestros 577 fragmentos serían centavos — pero exige reindexar pasando cada fragmento por un LLM.

**El dato que podemos usar hoy sin reindexar nada:**

> *"Pasar los **top-20** fragmentos al modelo es más efectivo que solo los top-10 o top-5."*

Nuestro `topK` está en **5**. Ese es un campo, no una reindexación.

---

## 4. Late chunking: mucho ruido, poca ganancia

Aparece mucho en blogs, así que vale medirlo. Los benchmarks de quien la propuso
([Jina AI](https://jina.ai/news/late-chunking-in-long-context-embedding-models/),
[Weaviate](https://weaviate.io/blog/late-chunking)) dan:

> *"Promediando tres modelos y cuatro conjuntos de datos, late chunking logró una mejora relativa
> del **3.63%** (1.9% absoluto)."*

Y el paper de taxonomía añade una advertencia importante: *"el chunking contextualizado mejoró la
recuperación en corpus pero **degradó** los resultados dentro del documento"*. Nuestro caso
—encontrar un inciso dentro de un reglamento— es precisamente el que se degrada.

**Conclusión: no aplica a nuestro problema.** Un 3.6% no arregla siete listas cortadas.

---

## 5. Cómo evalúan los equipos serios

Nuestra evaluación de 20 preguntas está **por debajo** del estándar, pero no lejos.

| Referencia | Tamaño recomendado |
|---|---|
| Golden dataset para empezar ([Qdrant](https://qdrant.tech/blog/rag-evaluation-guide/)) | **50–100 preguntas** con documento fuente y respuesta ideal |
| ARES (calibración automática) | ~150 muestras anotadas por humanos |
| Producción típica | 300 automáticas + 60 golden |

**Métricas estándar** ([DeepEval](https://deepeval.com/guides/guides-rag-evaluation),
[Patronus](https://www.patronus.ai/llm-testing/rag-evaluation-metrics)):

- **Recuperación:** precision@k, recall@k, MRR, nDCG
- **Generación:** faithfulness, relevancia, cobertura de citas, tasa de alucinación

**Lo que ya hacemos bien:** nuestras respuestas correctas salen del documento, no del modelo. Eso
es un golden dataset de verdad, y es la parte cara — *"los golden datasets con respuestas
verificadas a mano son costosos, lentos y subjetivos"* (Qdrant). Las nuestras están verificadas a
mano contra el PDF.

**Lo que falta:** llegar a 50 preguntas, y separar la métrica de recuperación de la de generación.
Hoy medimos la respuesta final; no medimos si el fragmento correcto llegó a estar entre los
recuperados. Son dos fallos distintos con dos arreglos distintos.

**Y algo que hicimos sin saber que era estándar:** las 4 preguntas de control miden *hallucination
rate*, que está en todas las listas de métricas de producción. Nuestro resultado ahí fue 0.

---

## 6. Lo que exige el sector salud, más allá del chunking

Para lo que Andrés quiere vender, esto importa tanto como el recall
([InformationWeek](https://www.informationweek.com/data-management/nobody-told-legal-about-your-rag-pipeline-why-that-s-a-problem)):

> *"En las bases de datos de RAG los datos se fragmentan, pero los metadatos de procedencia,
> propiedad y clasificación rara vez viajan con ellos."*

Prácticas concretas que citan para salud y finanzas:

- **El ID del fragmento debe ser la ruta de la sección**, no un hash — para poder citar `§ 164.404(c)(1)(A)` y que sea verificable
- Referencias cruzadas guardadas como metadatos
- Registro de auditoría de las decisiones de recuperación
- Citas explicables en cada respuesta
- Versionado del corpus (qué versión del reglamento respondió)

Ese último punto ya lo tenemos documentado: nuestro corpus es de marzo de 2013 y lo dijimos.

---

## Recomendación

**Una sola, con su trade-off:** hacer **chunking por estructura del § + parent-document
retrieval**, no subir el `chunkSize`.

HIPAA viene numerado (`§ 164.404`, `(c)`, `(1)`, `(A)`). Es el caso ideal para cortar por
estructura, y es donde la evidencia da 8–15 puntos de recall. Parent-document además es barato:
mismo índice, una consulta por ID.

**El trade-off:** cortar por estructura exige parsear la numeración del PDF, y el propio Edtek
advierte que *"la estructura tiene que ser legible; los PDFs varían muchísimo en qué tan limpiamente
se recupera su organización"*. Es más trabajo que cambiar un número, y puede fallar si el texto
extraído viene sucio. Subir el `chunkSize` es un campo; esto es un preprocesador.

**Antes de eso, el experimento de un minuto:** subir `topK` de 5 a 20 y repetir las 7 preguntas
incompletas. Anthropic midió que top-20 supera a top-5, y si los pedazos faltantes de las listas
están en las posiciones 6–20, aparecen sin reindexar nada. **Si funciona, sabemos que el problema
es de ranking y no de corte** — y eso cambia cuál de las dos correcciones hace falta.

Ese orden —el experimento barato antes de la obra grande— es el que separa medir de suponer.

---

## Metodología y límites

14 fuentes consultadas, 3 leídas completas. Sub-preguntas: estrategias de chunking para documentos
jerárquicos; evidencia medida de cada una; estándares de evaluación de RAG; si subir `chunkSize`
es corrección o parche; prácticas específicas del sector legal.

**Lo que no encontré:**

- **Ningún caso publicado de RAG sobre HIPAA con métricas.** Las cifras de 8–15 puntos vienen de
  corpus de contratos, no de reglamentos federales. Es analogía razonable, no evidencia directa.
- **El paper de taxonomía solo se pudo leer en abstract** — el PDF no era extraíble. Las cifras
  citadas son las del resumen de los autores, no de sus tablas.
- **Las cifras de recall por sección tienen una sola fuente** y sin paper detrás. Tratarlas como
  orden de magnitud.
