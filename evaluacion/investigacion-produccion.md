# Qué le falta a este RAG para ser un proyecto de verdad

*Investigación del 9 de agosto de 2026 · 12 fuentes · Escrita contra el estado real del sistema,
no contra un RAG genérico.*

## Resumen

Lo que falta no es una lista de mejoras: son **tres cosas que fallan por la misma razón** —el
sistema recupera bien y elige mal— más la instrumentación para demostrarlo.

Y hay un hallazgo que reordena todo lo demás: **`topK: 20` sin reranking es un antipatrón
documentado**, y explica un resultado que ya habíamos medido sin entenderlo.

---

## 1. El hallazgo: "Lost in the Middle"

El checklist de ingeniería de
[ActiveWizards](https://activewizards.com/blog/the-production-ready-rag-pipeline-an-engineering-checklist)
lo dice como regla dura:

> **"No devuelvas más de 10 documentos sin reranking."** Previene que el LLM ignore la
> información del medio del contexto.

Nosotros pusimos `topK: 20`. Y los datos propios encajan con la predicción, punto por punto:

| Lo medido | Lo que predice el fenómeno |
|---|---|
| Subir de 5 a 20 arregló 4 respuestas **y rompió la 16** | Más contexto sube el recall y baja la atención al medio |
| El elemento intruso del § 164.410 estaba en el **puesto 2** | El principio del contexto pesa mucho |
| El elemento **(E)** correcto estaba en el **puesto 15** | El medio-final es la zona que se pierde |

**El `topK: 20` no fue una solución: fue cambiar un problema por otro.** Compró recall pagando
con precisión. Lo que la literatura recomienda para eso no es bajar el `topK` —eso devuelve el
problema original— sino **recuperar 20 y reordenarlos con un reranker antes de pasárselos al
redactor**.

Anthropic lo midió: sumar reranking baja el fallo de recuperación de **2.9% a 1.9%**
([Anthropic Engineering](https://www.anthropic.com/engineering/contextual-retrieval)).

---

## 2. Lo que ya está resuelto (para no rehacerlo)

| Pieza | Estado |
|---|---|
| Embeddings locales, documentos que no salen del servidor | Hecho, es el argumento de venta |
| Corpus estructurado por secciones, con `§` y cita en metadatos | Hecho el 9 ago |
| Corpus vigente, con fecha de la propia fuente | Hecho — eCFR al 6 ago 2026 |
| Procedencia que viaja con el fragmento | Hecho — `source`, `citation`, `retrieved` |
| Golden dataset con respuestas verificadas a mano | Hecho — 20 preguntas, la parte cara |
| Preguntas de control (tasa de alucinación) | Hecho — 4/4, resultado 0 |
| Prompt que obliga a callarse | Hecho, y medido |
| Carga autenticada, sin puertos publicados | Hecho |
| Separar fallo de recuperación de fallo de generación | Hecho el 9 ago, leyendo la ejecución |

Eso no es poco: la mitad de la lista de producción de ActiveWizards ya está cubierta.

---

## 3. Lo que falta para arreglar los números medidos

Ordenado por cuánto mueve el resultado, no por dificultad.

### 3.1 Reranking — el que arregla el problema de fondo

Se recuperan 20 y un modelo pequeño los reordena por relevancia real antes de pasar los mejores
al redactor. Es una segunda pasada, cara pero solo sobre 20 candidatos
([ParadeDB](https://www.paradedb.com/blog/hybrid-search-in-postgresql-the-missing-manual)).

El modelo que encaja con el stack es **`bge-reranker-v2-m3`** — misma familia que BGE-M3, también
multilingüe, y corre en Ollama.

**Lo que arregla, de lo ya medido:** la pregunta 16 (rota por ruido) y el intruso del § 164.410
(que quedaría abajo, no en el puesto 2).

**El coste:** una llamada más por pregunta, en CPU sin GPU. La latencia sube.

### 3.2 Búsqueda híbrida (BM25 + vectorial)

Los embeddings buscan por significado y son **malos con cadenas exactas**: un `164.404` literal.
BM25 es exactamente lo contrario. Los sistemas de producción corren las dos y fusionan con
**Reciprocal Rank Fusion**.

En Postgres no hace falta infraestructura nueva: un índice **GIN sobre `tsvector`** al lado del
vectorial ([Ben Moataz](https://www.benmoataz.com/posts/hybrid-search-pgvector-bm25),
[DEV](https://dev.to/gabrielanhaia/hybrid-search-in-100-lines-bm25-pgvector-with-rrf-merge-58cn)).

**Por qué importa aquí en concreto:** el corpus está lleno de identificadores (`§ 164.404`,
`(c)(1)(A)`). Es el caso donde el vector solo pierde. *Cita textual de las fuentes: "hybrid-in-Postgres
es la decisión correcta cuando tus datos ya viven en Postgres y tus consultas mezclan significado
con identificadores".*

### 3.3 El índice vectorial

Hoy la tabla solo tiene la clave primaria: cada búsqueda recorre los 653 fragmentos uno por uno.
Con este corpus no se nota; a escala sí.

Configuración de producción citada para HNSW: **`m=16`, `ef_construction=64`**.

**Honesto: con 653 filas esto no cambia ningún número medible.** Se hace por lo que enseña y
porque es una línea, no porque arregle algo hoy.

### 3.4 Fusionar los fragmentos-encabezado

Dos de los 20 fragmentos recuperados en la prueba eran **solo el título** de la sección
(`## § 164.404 Notification to individuals.`). Ocupan un puesto y no aportan nada — un 10% del
contexto desperdiciado. Se arregla al cargar, pegando el encabezado al primer párrafo.

---

## 4. Lo que falta para poder enseñarlo

### 4.1 Evaluación automática con métricas separadas

Hoy la evaluación es manual y mide **la respuesta final**. El estándar es **RAGAS**, que separa
lo que hoy va junto ([Prem AI](https://blog.premai.io/rag-evaluation-metrics-frameworks-testing-2026/),
[Digital Applied](https://www.digitalapplied.com/blog/rag-system-metrics-recall-precision-faithfulness-2026)):

| Métrica | Qué mide | Objetivo citado |
|---|---|---|
| **Faithfulness** | Qué parte de la respuesta se puede verificar contra los fragmentos | 0.75 |
| **Answer relevancy** | Si responde lo que se preguntó | 0.80 |
| **Context precision** | Qué parte de lo recuperado era relevante | 0.70 |
| **Context recall** | Qué parte de lo necesario llegó a recuperarse | 0.80 |

Con estas cuatro, el fallo del § 164.410 se lee solo: **context precision baja, faithfulness
alta** — recuperó de más y el redactor lo usó.

*Nota: las cuatro se calculan con un LLM de juez. Eso cuesta dinero por corrida y hay que
presupuestarlo.*

### 4.2 Llegar a 50 preguntas

La guía de practicantes pone el golden dataset inicial en **50–100**
([Qdrant](https://qdrant.tech/blog/rag-evaluation-guide/)). Vamos por 20. Es la parte lenta y no
hay atajo: cada respuesta se saca a mano del documento.

### 4.3 Trazabilidad de extremo a extremo

Registrar por consulta: qué se preguntó, qué fragmentos se recuperaron con qué puntaje, qué
respondió, cuánto tardó, cuánto costó. Hoy eso vive en las ejecuciones de n8n y se puede leer
—lo hicimos— pero no queda guardado ni se puede sumar.

Sin esto, cada diagnóstico es una arqueología manual.

---

## 5. Lo que falta para cobrar por él

Esto no es "más ingeniería": es lo que separa un demo de algo que se le puede vender a una
clínica. Fuente: [Kiteworks](https://www.kiteworks.com/hipaa-compliance/healthcare-rag-hipaa-compliance-controls/).

- **Registro de auditoría.** *"HIPAA exige un rastro de auditoría completo de cada acceso a PHI:
  quién consultó qué, cuándo y con qué rol."* Hoy no existe.
- **Control de acceso al recuperar, no después.** *"Filtrar durante la recuperación, no después;
  el dato no autorizado nunca debe entrar en la tubería."* Hoy cualquier consulta ve todo.
- **Dos vectores de fuga de PII: la ingesta y la inferencia.** El corpus actual es normativa
  pública, así que no aplica todavía — el día que entre un documento de cliente, sí.
- **Defensa contra inyección de prompt.** Un documento cargado puede traer instrucciones dentro.
- **Control de gasto por usuario.** Hoy el único freno es el tope de la cuenta de OpenAI.
- **Un BAA con el proveedor del modelo.** Si el redactor es una API externa y el documento es
  PHI, hace falta acuerdo firmado. **Esto empuja hacia el modelo local**, y ahí el argumento
  "todo se queda en tu servidor" deja de ser marketing y pasa a ser el requisito.

---

## 6. Lo que NO hace falta

Tan importante como la lista de arriba.

- **Caché de consultas, enrutamiento de modelos, degradación por coste.** Son optimizaciones para
  volumen. Con un usuario haciendo 20 preguntas no ahorran nada.
- **Cambiar de base vectorial.** Postgres con pgvector aguanta millones de vectores. Cambiar a
  Pinecone o Qdrant aquí sería gasto y una dependencia más.
- **Reindexar con Contextual Retrieval de Anthropic.** Da los mejores números medidos, pero exige
  pasar cada fragmento por un LLM. **El chunking por estructura ya recogió buena parte de esa
  ganancia** — se evalúa después de medir con reranking, no antes.
- **Reescribir nada en Python.** Todo lo de arriba se puede montar en n8n con lo que ya hay.

---

## Recomendación

**Una, con su trade-off: reranking primero, y medir antes y después con las mismas 20 preguntas.**

Es lo que ataca la causa que los datos ya señalan —recuperación buena, elección mala— y es el
único cambio que arregla **los dos fallos abiertos a la vez**: el ruido que rompió la 16 y el
intruso del § 164.410.

**El trade-off:** la latencia sube. Hoy la mediana es 16 s y el reranker añade una pasada por CPU
sin GPU. Si sube a 25–30 s, un chat en vivo se siente lento — y eso importa para una demo. Se
mide, no se supone.

**El orden después:** híbrida (BM25) → registro de trazas → llegar a 50 preguntas → RAGAS.
El bloque de cumplimiento se monta cuando haya un cliente real, no antes: hacerlo hoy sería
construir controles para datos que todavía no existen.

---

## Metodología y límites

12 fuentes consultadas, 1 leída completa. Frentes investigados: qué separa un RAG de demo de uno
de producción; búsqueda híbrida y reranking sobre Postgres; estándares de evaluación; requisitos
del sector salud.

**Lo que no encontré:**

- **Ninguna cifra medida de cuánto sube la latencia** un reranker en CPU sin GPU. Todas las
  fuentes lo dan por asumido. Hay que medirlo aquí.
- **Los objetivos de RAGAS (0.75 / 0.8 / 0.7 / 0.8) vienen de una sola fuente** y sin estudio
  detrás. Tratarlos como orden de magnitud.
- **La regla de "no más de 10 sin reranking"** se cita como práctica de ingeniería, no como
  resultado de un experimento publicado. Lo que sí es dato duro es que **nuestra propia medición
  la respalda**: subir a 20 rompió una respuesta que funcionaba.
