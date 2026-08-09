# RAG evaluation — 20 questions

> **Note on language.** The questions and the hand-verified answers below are **in Spanish on
> purpose**: they are asked in Spanish against an English regulation, and whether the multilingual
> embedding model bridges that gap is part of what this measures. Translating them would erase the
> experiment. Everything else — method, criteria and results — is in English.

**Rounds 1 and 2 — document under test:** `hipaa-simplification-201303.pdf` — HIPAA Administrative
Simplification, 45 CFR Parts 160, 162 and 164 (unofficial version, amended through **26 March
2013**). 577 fragments, indexed in 8 min 8 s.

**Round 3 — same 20 questions, restructured corpus:** 148 sections pulled from the eCFR API,
current as of 6 August 2026. 653 fragments. Details in that round's section below.

**Embedding model:** BGE-M3 (1024 dimensions), local on the server, no GPU.
**Writing model:** `gpt-5-mini` via API.

---

## How this evaluation works

The correct answers **come out of the document** — not from the model, and not from anyone's
memory. If the ruler is wrong, the number is worthless.

Two kinds of question:

- **1 to 16 — answerable from the document.** They measure whether the system finds the answer and
  cites it correctly.
- **17 to 20 — NOT answerable from the document.** They measure whether the system stays quiet. It
  must reply exactly: *"No encontré eso en los documentos cargados."*

**The control questions are the half that matters.** A RAG that gets 16 out of 16 right but invents
the other 4 is useless to a clinic: nobody can tell which of its answers is real.

⚠️ **Question 19 is a double trap:** there is no official US government "HIPAA certification". It is
a product sold by private consultancies. If the model gives a price or a procedure, it made the
whole thing up.

**Round rule: one question, one answer, recorded.** No rephrasing until it gets it right — in
production the customer asks once and lives with whatever comes back.

---

## Questions answerable from the document

| # | Question *(Spanish)* | Section | Correct answer, verified by hand | RAG answer | OK? |
|---|---|---|---|---|---|
| 1 | ¿Qué plazo tiene una entidad para notificar a los individuos afectados por una brecha? | § 164.404 | Sin demora irrazonable, máximo 60 días calendario desde el descubrimiento |Sin demora indebida y, en ningún caso, más tarde de 60 días calendario después del descubrimiento de la brecha. Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights) | |
| 2 | ¿A partir de cuántos individuos afectados hay que notificar a los medios de comunicación? | § 164.406 | Más de 500 residentes de un estado o jurisdicción |A partir de 500 individuos.

Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights) — sección § 164.406: "For a breach of unsecured protected health information involving more than 500 residents of a State or jurisdiction, a covered entity shall... notify prominent media outlets serving the State or jurisdiction." | |
| 3 | ¿Cuándo debe notificarse una brecha al Secretary? | § 164.408 | Depende del tamaño. ≥500 personas: al mismo tiempo que la notificación a los individuos.<br>&lt;500: en un reporte anual, máximo 60 días después de cerrar el año calendario. § 164.408(b) y (c) |Tras el descubrimiento de la brecha: notificar al Secretary "following the discovery of a breach" y "without unreasonable delay and in no case later than 60 calendar days after discovery of a breach." Para brechas de 500 o más individuos: notificar "contemporaneously with the notice required by § 164.404(a) and in the manner specified on the HHS Web site." Para menos de 500: mantener un registro y notificar "not later than 60 days after the end of each calendar year." (Documento: Combined Regulation Text of All Rules, HHS Office for Civil Rights) | |
| 4 | ¿Qué plazo tiene un business associate para notificar una brecha a la entidad cubierta? | § 164.410 | No más de 60 días después de descubrir la brecha |Plazo: "without unreasonable delay and in no case later than 60 calendar days after discovery of a breach." (§ 164.410, Combined Regulation Text of All Rules — HHS Office for Civil Rights). | |
| 5 | ¿Cuántos años deben conservarse las políticas y procedimientos de seguridad? | § 164.316 | 6 años desde su creación o desde la última fecha en que estuvo vigente, la que sea posterior. § 164.316(b)(2)(i) |6 años.

Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights). Frase recuperada: "Retain the documentation required by paragraph (b)(1) of this section for 6 years from the date of its creation or the date when it last was in effect, whichever is later." | |
| 6 | ¿Cuál es la definición de *business associate*? | § 160.103 | Persona o entidad que, por cuenta de una entidad cubierta y sin ser parte de su personal, crea, recibe, mantiene o transmite PHI para una función regulada por la norma (procesamiento de reclamaciones, análisis de datos, revisión de utilización, aseguramiento de calidad). § 160.103 |Definición: "Business associate: (1) Except as provided in paragraph (4) of this definition, business associate means, with respect to a covered entity, a person who: (i) On behalf of such covered entity or of an organized health care arrangement (as defined in this section) in which the covered entity participates, but other than in the capacity of a member of the workforce of ... receives, maintains, or transmits protected health information on behalf of the business associate. (2) A covered entity may be a business associate of another covered entity. (3) Business associate includes: (i) A Health Information Organization, E-prescribing Gateway, or other person that provides data transmission services with respect to protected health information to a covered entity and that requires access on a routine basis to such protected health information. (ii) A person that offers a personal health record to one or more individuals on behalf of a covered entity. (iii) A subcontractor that creates, receives, maintains, or transmits protected health information on behalf of the business associate. (4) Business associate does not include: (i) A health care provider, with respect to disclosures by a covered entity to the health care provider concerning the treatment of the individual. (ii) A plan sponsor, with respect to disclosures by a group health plan..."

Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights), § 160.103 Definitions. | |
| 7 | ¿Cuál es la definición de *breach*? | § 164.402 | Adquirir, acceder, usar o divulgar PHI de forma no permitida por la Subparte E, comprometiendo su seguridad o privacidad.<br>**EXCLUYE:** (i) acceso no intencional de buena fe por personal autorizado, sin uso posterior indebido; (ii) divulgación inadvertida entre personas autorizadas de la misma entidad; (iii) casos donde de buena fe se cree que el receptor no pudo retener la información.<br>Todo lo demás se **presume** brecha salvo que se demuestre baja probabilidad de compromiso, con evaluación de riesgo sobre 4 factores: naturaleza y alcance del PHI (y probabilidad de reidentificación), quién lo recibió, si fue realmente adquirido o visto, y cuánto se mitigó el riesgo. § 164.402 |"Breach means the acquisition, access, use, or disclosure of protected health information in a manner not permitted under subpart E of this part which compromises the security or privacy of the protected health information."

Fuente: HIPAA Administrative Simplification Regulation Text — Combined Regulation Text of All Rules (HHS Office of Civil Rights, March 2013). | |
| 8 | ¿Cuáles son las tres categorías de salvaguardas de la Security Rule? | § 164.308, 164.310, 164.312 | Tres: administrativas (§ 164.308), físicas (§ 164.310) y técnicas (§ 164.312) |Las tres categorías son: salvaguardas administrativas (§164.308), físicas (§164.310) y técnicas (§164.312).

Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights) | |
| 9 | ¿Qué plazo hay para darle a un individuo acceso a su información de salud? | § 164.524 | 30 días desde que recibe la solicitud. Extensible UNA sola vez por 30 días más, avisando por escrito dentro del plazo original el motivo y la fecha en que responderá. § 164.524(b)(2) |La entidad cubierta debe actuar sobre la solicitud de acceso no más de 30 días desde la recepción de la solicitud (§ 164.524).
Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights). | |
| 10 | ¿Qué plazo hay para responder a una solicitud de enmienda? | § 164.526 | 60 días desde que recibe la solicitud. Extensible UNA sola vez por 30 días más, avisando por escrito el motivo y la fecha. § 164.526(b)(2) |El responsable debe actuar sobre la solicitud de enmienda a más tardar 60 días desde su recepción. Puede prorrogarse una sola vez por hasta 30 días si, dentro del plazo inicial, el responsable entrega al interesado una declaración escrita de las razones del retraso y la fecha en que completará la actuación. Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights). | |
| 11 | ¿Qué período cubre el *accounting of disclosures*? | § 164.528 | 6 años anteriores a la fecha de la solicitud. El individuo puede pedir un período menor. § 164.528(a)(1) y (a)(3) |Cubre los seis años anteriores a la fecha en que se solicita la accounting of disclosures. (Fuente: Combined Regulation Text of All Rules, HHS Office of Civil Rights) | |
| 12 | ¿Cuáles son los montos de las multas civiles por violación? | § 160.404 | Cuatro niveles según culpabilidad (violaciones desde 18-feb-2009), todos con tope de $1,500,000/año por violaciones idénticas:<br>· No sabía ni podía saber con diligencia razonable: $100–$50,000 por violación<br>· Causa razonable, sin negligencia deliberada: $1,000–$50,000<br>· Negligencia deliberada CORREGIDA en 30 días: $10,000–$50,000<br>· Negligencia deliberada NO corregida: mínimo $50,000, sin máximo por violación<br>(Antes del 18-feb-2009: $100 por violación, tope $25,000/año.) § 160.404(b) |Antes del 18‑feb‑2009: hasta $100 por violación; hasta $25,000 por violaciones idénticas en un año calendario.

A partir del 18‑feb‑2009:

(i) entidad no sabía (con diligencia razonable): $100–$50,000 por violación; tope $1,500,000 por violaciones idénticas en un año.
(ii) por causa razonable (no willful neglect): $1,000–$50,000 por violación; tope $1,500,000.
(iii) willful neglect corregido en 30 días: $10,000–$50,000 por violación; tope $1,500,000.
Fuente: Combined Regulation Text of All Rules — HIPAA Administrative Simplification Regulation Text (HHS Office for Civil Rights, March 2013). | 2da respuesta Según Combined Regulation Text of All Rules (HHS Office of Civil Rights), §160.404:

Para violaciones previas al 18-feb-2009: "In the amount of more than $100 for each violation; or In excess of $25,000 for identical violations during a calendar year." (Fuente: Combined Regulation Text of All Rules)

Para violaciones a partir del 18-feb-2009:

Si se establece que no se sabía: "In the amount of less than $100 or more than $50,000 for each violation; or In excess of $1,500,000 for identical violations during a calendar year."
Si fue por causa razonable y no por negligencia deliberada: "In the amount of less than $1,000 or more than $50,000 for each violation; or In excess of $1,500,000 for identical violations during a calendar year."
Si fue por negligencia deliberada y se corrigió durante 30 días: "In the amount of less than $10,000 or more than $50,000 for each violation; or In excess of $1,500,000 for identical violations during a calendar year."
Si fue por negligencia deliberada y no se corrigió durante 30 días: "In the amount of less than $50,000 for each violation; or In excess of $1,500,000 for identical violations during a calendar year."
Fuente: Combined Regulation Text of All Rules (HHS Office of Civil Rights), §160.404. |
| 13 | ¿Qué factores se consideran para determinar el monto de una multa? | § 160.408 | Cinco, y cada uno puede ser atenuante o agravante:<br>(a) Naturaleza y alcance de la violación (nº de individuos afectados, duración)<br>(b) Naturaleza y alcance del daño (físico, financiero, reputacional, o si impidió obtener atención médica)<br>(c) Historial de cumplimiento previo (reincidencia, correcciones, respuesta a asistencia técnica y a quejas)<br>(d) Condición financiera de la entidad (dificultades, si la multa pondría en riesgo su capacidad de dar atención, tamaño)<br>(e) Otros asuntos que la justicia requiera. § 160.408 |Los factores son:

(a) La naturaleza y extensión de la violación — puede incluir, entre otros, el número de individuos afectados y el período de tiempo en que ocurrió la violación.
(b) La naturaleza y extensión del daño resultante — puede incluir, entre otros, si la violación causó daño físico; daño financiero; daño a la reputación de una persona; y si impidió la capacidad de una persona para obtener atención médica.
(c) El historial de cumplimiento previo con la simplificación administrativa.
Fuente: Combined Regulation Text of All Rules (HHS Office for Civil Rights), §160.408. | 2da respuesta Se consideran, entre otros, los siguientes factores:

La naturaleza y extensión de la violación, incluyendo: el número de individuos afectados y el período de tiempo durante el cual ocurrió la violación.
La naturaleza y extensión del daño resultante, incluyendo: si causó daño físico; si resultó en daño financiero; si dañó la reputación del individuo; y si impidió la capacidad del individuo para obtener atención de salud.
El historial de cumplimiento previo con las disposiciones de simplificación administrativa.
Si la entidad tuvo dificultades financieras que afectaron su capacidad para cumplir; si la imposición de la multa pondría en riesgo su capacidad para seguir proveyendo o pagando atención de salud; y el tamaño de la entidad.
Cualesquier otros asuntos que la justicia requiera.
Fuente: Combined Regulation Text of All Rules — HIPAA Administrative Simplification Regulation Text (§160.408).|
| 14 | ¿Qué elementos debe contener la notificación de brecha a los individuos? | § 164.404 | Cinco elementos, en lenguaje sencillo:<br>(A) Descripción breve de qué pasó, con fecha de la brecha y fecha del descubrimiento<br>(B) Tipos de PHI involucrados (nombre, SSN, fecha de nacimiento, dirección, nº de cuenta, diagnóstico, etc.)<br>(C) Pasos que el individuo debe tomar para protegerse<br>(D) Qué está haciendo la entidad para investigar, mitigar y evitar que se repita<br>(E) Datos de contacto: teléfono gratuito, correo, sitio web o dirección postal<br>§ 164.404(c) |primera vez fallo a los 10 min segunda fallo despues de 5 intentos  |  Una breve descripción de lo ocurrido, incluida la fecha de la brecha y la fecha del descubrimiento, si se conoce;
Una descripción de los tipos de información de salud no asegurada involucrada (por ejemplo: nombre completo, número de seguro social, fecha de nacimiento, dirección, número de cuenta, diagnóstico, código de discapacidad u otros tipos);
Cualquier paso que las personas deban tomar para protegerse del posible daño resultante;
Una breve descripción de lo que la entidad está haciendo para investigar la brecha, mitigar el daño y proteger contra futuras brechas;
Procedimientos de contacto para que las personas pregunten o obtengan más información, que incluyan número telefónico gratuito, dirección de correo electrónico, sitio web o dirección postal;
La notificación debe redactarse en lenguaje claro.
Fuente: Combined Regulation Text of All Rules, HHS Office of Civil Rights (HIPAA Breach Notification Rule).|
| 15 | ¿Qué debe incluir el *Notice of Privacy Practices*? | § 164.520 | Ocho elementos, en lenguaje sencillo:<br>(i) Encabezado con el texto LITERAL: "THIS NOTICE DESCRIBES HOW MEDICAL INFORMATION ABOUT YOU MAY BE USED AND DISCLOSED AND HOW YOU CAN GET ACCESS TO THIS INFORMATION. PLEASE REVIEW IT CAREFULLY."<br>(ii) Usos y divulgaciones, con al menos un ejemplo para tratamiento, pago y operaciones<br>(iii) Declaraciones separadas si hay recaudación de fondos, plan de grupo o underwriting<br>(iv) Derechos del individuo (restricciones, comunicaciones confidenciales, acceso, enmienda, accounting, copia en papel)<br>(v) Deberes de la entidad, incluida la de notificar brechas<br>(vi) Derecho a quejarse ante la entidad y ante el Secretary, sin represalias<br>(vii) Nombre o cargo y teléfono de contacto<br>(viii) Fecha de entrada en vigor<br>§ 164.520(b)(1) |Debe incluir, según §164.520:

Derecho a aviso: "an individual has a right to adequate notice of the uses and disclosures of protected health information ... and of the individual's rights and the covered entity's legal duties..." (§164.520(a)(1)).
Quejas: "The notice must contain a statement that individuals may complain to the covered entity and to the Secretary ... a brief description of how the individual may file a complaint ... and a statement that the individual will not be retaliated against for filing a complaint." (§164.520(b)(1)(vi)).
Contact: "The notice must contain the name, or title, and telephone number of a person or office to contact for further information ..." (§164.520(b)(1)(vii)).
Fecha de vigencia: "The notice must contain the date on which the notice is first in effect ..." (§164.520(b)(1)(viii)).
Además existen "optional elements" para información adicional si la entidad limita usos o divulgaciones (§164.520(b)(2)(i)).
Fuente: HIPAA Administrative Simplification Regulation Text, March 2013 — §164.520. | |
| 16 | ¿En qué casos NO aplica el estándar de *minimum necessary*? | § 164.502 | Seis casos:<br>(i) Divulgaciones a un proveedor de salud, o solicitudes de este, para TRATAMIENTO<br>(ii) Usos o divulgaciones hechas al propio individuo<br>(iii) Usos o divulgaciones hechas con autorización del individuo (§ 164.508)<br>(iv) Divulgaciones al Secretary para investigar cumplimiento<br>(v) Usos o divulgaciones requeridos por ley (§ 164.512(a))<br>(vi) Usos o divulgaciones requeridos para cumplir con este subcapítulo<br>§ 164.502(b)(2) |Primero intetno error Max 5 Iterations segundo intento bnNo aplica a (según Combined Regulation Text of All Rules):

Divulgaciones a o solicitudes por un proveedor de atención médica para tratamiento.
Usos o divulgaciones hechas al individuo, según lo permitido o requerido en los párrafos indicados.
Usos o divulgaciones efectuadas conforme a una autorización (§ 164.508).
Divulgaciones realizadas al Secretario de conformidad con la subparte C del parte 160. | |

## Control questions — the correct answer is silence

| # | Question *(Spanish)* | Expected answer | RAG answer | OK? |
|---|---|---|---|---|
| 17 | ¿Cuál es la multa máxima bajo el GDPR? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |
| 18 | ¿Qué dice esta norma sobre el uso de inteligencia artificial o modelos de lenguaje? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |
| 19 | ¿Cuánto cuesta obtener la certificación oficial HIPAA? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |
| 20 | ¿Qué obligaciones aplican a un laboratorio clínico en Colombia? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |

---

## Result — rounds 1 and 2

**Grading rule, fixed before counting:** an answer counts as correct if a practice administrator
could act on it without getting it wrong. Incomplete ≠ incorrect, but it isn't a hit either — it's
counted separately.

| | Value |
|---|---|
| ✅ Complete and correct (of 16) | **7** — questions 1, 3, 4, 5, 6, 8, 10 |
| ⚠️ Correct but incomplete (of 16) | **7** — questions 7, 9, 11, 12, 13, 15, 16 |
| ❌ Contained a wrong figure | **1** — question 2 |
| ❌ No answer at all (system failure) | **1** — question 14 |
| ✅ Control questions (of 4) | **4 of 4** |
| **Invented answers** | **0** |

**Two numbers, depending on how strict you are:**

| Criterion | Result |
|---|---|
| Strict (complete answers only) | **11 / 20 — 55%** |
| Lenient (complete + incomplete but not wrong) | **18 / 20 — 90%** |

That gap between 55% and 90% **is the finding**, not a flaw in the method: the system almost never
lies, but it very often falls short. For a clinic, a half-answer that sounds complete is more
dangerous than one that says "I don't know".

### What went right

**Zero hallucinations across 20 questions.** All 4 controls replied with exactly *"No encontré eso
en los documentos cargados"*, including the trap about the HIPAA certification that doesn't exist.
None of the other 16 answers asserts anything false — the ones that fail, fail by omission.

**Cross-language retrieval confirmed.** Every question was asked in Spanish against an English
document. Retrieval worked in all 20 cases: multilingual BGE-M3 delivers.

### Question 2 — the subtlest error of all

The RAG summarised it as *"a partir de 500 individuos"* ("from 500 individuals"), while the verbatim
text it had itself retrieved says **"more than 500 residents of a State or jurisdiction"**.

*More than 500* excludes exactly 500. *From 500* includes it. A breach affecting exactly 500 people
does **not** require media notification, and the summary says it does.

The system retrieved the right text and got the summary wrong. That is the class of error nobody
catches by reading the answer — only by comparing it against the source, which is precisely why
this evaluation exists.

### The 7 incomplete ones share a single cause

| # | What was missing |
|---|---|
| 7 | The exclusions and the breach presumption (gave only the definition) |
| 9 | The 30-day extension |
| 11 | That the individual may request a shorter period |
| 12 | The fourth penalty tier — willful neglect **not** corrected, the most severe one |
| 13 | Factors (d) and (e) out of five |
| 15 | Four of the eight elements, including the mandatory verbatim header |
| 16 | Two of the six cases |

**All of them are truncated lists.** The system finds where the enumeration starts and delivers the
first items. It's the same failure diagnosed in question 14, except there the cut came so early the
agent couldn't answer at all.

**It isn't the model: it's the chunking.** Fragments of 1000 characters split the long lists, and no
search recovers what got separated from its heading.

> **Written at the end of round 2, and only half right.** Round 3 showed the missing fragments
> *existed* — they were ranked below the cutoff. Chunking was part of it; ranking was the rest. The
> paragraph is left as written because how the diagnosis evolved is worth more than a tidy one.

### Measured latency and reliability

| | Value |
|---|---|
| Median | 16 s |
| Mean | 18 s |
| Worst completed | 262 s |
| Timeout failure | 604 s |
| Queries that failed and had to be repeated | 3 of 23 |

### The three fixes that come out of this

1. **`chunkSize` 1000 → 2000, or semantic splitting.** Attacks the cause of the 7 incompletes and
   of question 14's failure. Requires reindexing all 577 fragments (~8 min).
2. **`reasoning_effort: low`.** Answering from already-retrieved fragments is not a reasoning task;
   the model was thinking about a problem retrieval had already solved.
3. **A 30–60 s timeout with a message to the user.** The current cutoff is 604 s, which in a chat is
   the same as having none.

**The before and after of applying #1 to these same 20 questions is the measurement that makes this
project worth anything.**

> **What actually happened:** fix #1 was never applied. Research showed chunk size is the wrong
> lever, and the real problem turned out to be the input format — the corpus was rebuilt from the
> eCFR API instead. See round 3.

---

## Questions to watch — the ones with a trap inside

Written down **before** measuring, so the results couldn't be rationalised afterwards.

- **Q3** has **two cases** (≥500 and <500). It will most likely answer only the first. That isn't a
  wrong answer: it's an **incomplete one that looks complete**, and it leaves an administrator
  believing they have nothing to report when they have a pending annual obligation.
- **Q5** is not plain "6 years". The *"whichever is later"* changes the count: a policy in force for
  ten years is kept for 6 years **from when it stopped being used**.
- **Q7** has three layers: definition, exclusions, presumption. The one that matters is the third —
  it reverses the burden of proof.
- **Q9 against Q10.** Access is 30 days, amendment is 60. Two similar rights with different
  deadlines: if it confuses them, it retrieved the wrong fragment — and the wrong answer looks
  exactly as confident as the right one.
- **Q11** is 6 years **of a subset**: treatment, payment and operations are excluded.
- **Q15** is the best hallucination detector of the 16: the header is **mandatory verbatim text**. A
  model answering from memory will paraphrase it.

---

## Note on corpus currency

This text is amended **through March 2013**. The civil penalty amounts in § 160.404 are adjusted
for inflation annually, so the figures the system reports are the 2013 ones, not the current ones.

**That is not a RAG failure: it is a corpus failure.** And it is exactly the limitation to tell a
client before they find it on their own — a RAG is only as current as the documents loaded into it,
and keeping them up to date is part of the service, not an extra.

**Practical consequence:** question 12's answers are not counted as a system failure when they match
the document. They are noted here.

> **Resolved in round 3.** The corpus was rebuilt from the eCFR API, which reports its own effective
> date. Verified afterwards: the § 160.404 amounts are unchanged in the 2026 text — but the section
> now points to 45 CFR Part 102 for the inflation-adjusted figures, and Part 102 is not loaded. The
> limitation moved rather than disappearing.

---

# Round 3 — section-based corpus (9 August 2026)

**What changed against the previous two rounds:** one variable, the corpus.

| | Rounds 1 and 2 | Round 3 |
|---|---|---|
| Source | March 2013 PDF, 115 pages | eCFR API, current as of 6 Aug 2026 |
| Unit | 577 fragments cut every 1000 characters | 653 fragments, **none crosses a section boundary** |
| Metadata | nothing usable | `seccion`, `citation`, `source`, `retrieved` on every one |

`topK` stays at 20, the prompt untouched and the model untouched, **deliberately**: change more than
one thing and the number can't tell you which one moved it.

**Two criteria fixed before counting:**

1. **A wrong citation counts as a failure.** The prompt orders the model to cite, and for what this
   is meant to sell, a citation that doesn't check out is worse than no citation: whoever opens it
   and finds nothing stops trusting the other nineteen answers.
2. **Mixing in content from another section counts as a failure**, even when the text exists and is
   correctly cited. Its own category: *"complete, with a foreign element"*.

## Per-question verdicts

| # | Section | Verdict | Note |
|---|---|---|---|
| 1 | § 164.404 | ✅ | Correct. First time it cites the exact section instead of the PDF's name |
| 2 | § 164.406 | ✅ | **Fixed.** Round 2 said "from 500"; now "more than 500" |
| 3 | § 164.408 | ✅ | Both cases complete. Round 2 pulled in a sentence from § 164.404; this one doesn't |
| 4 | § 164.410 | ✅ | Same deadline and near-identical wording to Q1, in a different section. Didn't cross them |
| 5 | § 164.316 | ✅ | Includes the "whichever is later" qualifier |
| 6 | § 160.103 | ❌ | **Incomplete.** Missing `(1)(i)`, the core definition — see the diagnosis below |
| 7 | § 164.402 | ❌ | **Incomplete.** Base definition only: missing the 3 exclusions and the 4 risk factors |
| 8 | § 164.308/310/312 | ❌ | **Right content, wrong citation:** cited § 164.530 and § 164.304 |
| 9 | § 164.524 | ✅ | **Fixed.** Round 2 gave only "30 days"; now with the extension, the notice and the date |
| 10 | § 164.526 | ✅ | 60 days, extension and notice. Didn't cross it with Q9 |
| 11 | § 164.528 | ✅ | Includes the shorter-period-on-request qualifier |
| 12 | § 160.404 | ✅ | All four tiers with figures, plus the pre-Feb-2009 case |
| 13 | § 160.408 | ✅ | All five factors with their examples |
| 14 | § 164.404 | ✅ | The five elements + plain language. **Round 2 never answered it (604 s timeout)** |
| 15 | § 164.520 | ❌ | Cites individual rights as `(b)(1)(v)` when they are `(iv)`, and files `(b)(1)(iii)` — mandatory — under optional |
| 16 | § 164.502 | ✅ | All six cases exactly. **This was round 2's only false negative** |
| 17 | control | ✅ | Exact phrase |
| 18 | control | ✅ | Exact phrase |
| 19 | control | ✅ | The trap about the certification that doesn't exist |
| 20 | control | ✅ | Exact phrase |

## Result — round 3

| | PDF, topK 5 | PDF, topK 20 | **Section corpus** |
|---|---|---|---|
| Complete and correct (of 16) | 7 | 11 | **12** |
| Failures (of 16) | 9 | 5 | **4** |
| False negatives | 0 | **1** | **0** |
| Control (of 4) | 4 | 4 | **4** |
| **Hallucinations** | **0** | **0** | **0** |
| **Strict score** | 11/20 — 55% | 15/20 — 75% | **16/20 — 80%** |

### What this number does NOT say

**80% with n=20 carries ±18 points.** Going from 75% to 80% is **one question of difference** and
sits inside the noise. No statistical improvement can be claimed from this sample.

**And this round was graded more harshly than the previous two.** It added *"a wrong citation counts
as a failure"* — a rule that wasn't even applicable in rounds 1 and 2, because every answer cited
the name of the whole PDF and there was no citation to check. Under the old rule, questions 8 and 15
would have passed and the result would read **18/20 — 90%**.

The bar was raised because there is more to measure now, not to inflate the number. Both figures are
written down.

### What it does say, and doesn't depend on the percentage

**Nothing that worked stopped working.** That is the real difference from the previous change:

| Raising `topK` from 5 to 20 | fixed 4 · **broke 1** |
| Changing the corpus | fixed 3 (Q2, Q9, Q16) + recovered Q14, which previously didn't answer at all · **broke 0** |

The `topK` change was a trade. This one cost nothing.

**Citations went from decorative to verifiable.** Before: *"Combined Regulation Text of All Rules"* —
the name of a 115-page PDF. Now: `45 CFR 164.404` with its URL. That adds no points, and it is what
matters most for selling this to a clinic.

**And that is exactly why two new failures appeared** (Q8 and Q15, wrong citations). They are not
new failures of the system: they are failures that used to be **invisible**. A citation pointing at
the entire document can never be wrong.

**All four failures have an identified cause**, which was impossible in the previous rounds:

- **Q6, Q7, Q15** — rank dilution. The term in the question (*business associate*, *breach*, *notice
  of privacy practices*) appears across many sections, and the fragments from the one that
  **defines** it lose slots to the seventeen that only **mention** it. Measured on Q6: 3 slots out
  of 20 for the right section.
- **Q8** — pure generation. The three categories were right; the citations were invented.

The first three are what reranking and hybrid search attack. The fourth is a prompt fix.

### Diagnosing Q6 — by reading what was retrieved, not the answer

This is the first failure that could be diagnosed by looking at the retrieved fragments
(execution 298), something impossible in the earlier rounds.

**The fragment with the core definition never arrived.** Rank 1 ends exactly at
*"...business associate means, with respect to a covered entity, **a person who:**"*, and rank 5
starts at *"**(ii)** Provides... legal, actuarial..."*. Between them sits the missing `(1)(i)` —
literally what the question asks for. **It exists in the database and fell below the cutoff.**

**And the cause is right there:** of the 20 retrieved fragments, **only 3 came from § 160.103**. The
other 17 came from § 164.504 (×5), § 164.502 (×4), § 164.410 (×3), § 164.314 (×2), § 160.310 (×2),
§ 160.402 and § 162.923.

Every one of them talks **about** business associates; none **defines** them. The term appears
throughout the regulation, so semantic search returned the whole topic and left three slots out of
twenty to the only section that answers.

**Textbook case for the two pending fixes:** hybrid search would find `160.103` as an exact string,
and a reranker would lift the fragment that defines above the ones that merely mention.

### Two hypotheses the data killed mid-round

Both were written down as they formed, and both were wrong.

**First, after questions 6 and 7:** *"list questions fail, single-fact questions pass."* Q12 killed
it — four penalty tiers with their figures, answered completely.

**Second, replacing it:** *"it fails when the section is huge."* That one fit better for a while:

| § 160.404 (penalties) | 48 lines | ✅ |
| § 160.408 (factors) | short | ✅ |
| § 160.103 (definitions) | dozens of definitions | ❌ |
| § 164.402 (*breach*) | long, with exclusions and factors | ❌ |

**Q16 killed it too** — § 164.502 is one of the largest sections in the corpus and the answer came
back perfect.

The third hypothesis — dilution by how popular the term is across the corpus — fits all twenty
cases. **It is written here as a hypothesis, not announced as a conclusion**, and it gets tested by
the reranking work. Two died already; the third doesn't get to skip the queue.

### The methodological warning that outranks the score

Question 14 was run **twice under an identical configuration**. The first run returned the five
elements **plus one from § 164.410 that doesn't belong**; the second returned the five clean.
Nothing changed between them.

**The model is not deterministic.** One run per question is not a stable measurement, so this 80%
carries two sources of noise: the sampling one and the model's own. A rigorous evaluation would run
each question several times and average.

