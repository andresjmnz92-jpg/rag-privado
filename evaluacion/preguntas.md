# Evaluación del RAG — 20 preguntas

**Documento evaluado:** `hipaa-simplification-201303.pdf` — HIPAA Administrative Simplification,
Regulation Text, 45 CFR Partes 160, 162 y 164 (versión no oficial, con enmiendas hasta el
**26 de marzo de 2013**). 577 fragmentos indexados en 8 min 8 s.

**Modelo de embeddings:** BGE-M3 (1024 dimensiones), local en el servidor, sin GPU.
**Modelo redactor:** `gpt-5-mini` vía API.

---

## Cómo funciona esta evaluación

Las respuestas correctas **salen del documento**, no del modelo ni de nadie de memoria. Si la
vara de medir está mal, el número no vale nada.

Las preguntas son de dos tipos:

- **1 a 16 — tienen respuesta en el documento.** Miden si el sistema la encuentra y la cita bien.
- **17 a 20 — NO tienen respuesta en el documento.** Miden si el sistema se calla. Debe responder
  exactamente: *"No encontré eso en los documentos cargados."*

**Las de control son la mitad que importa.** Un RAG que responde bien 16 de 16 pero se inventa
las otras 4 no sirve para una clínica: nadie puede distinguir cuál de sus respuestas es real.

⚠️ **La pregunta 19 es trampa doble:** no existe una "certificación HIPAA" oficial del gobierno
de Estados Unidos. Es un producto que venden consultoras privadas. Si el modelo da un precio o
un procedimiento, se lo inventó completo.

**Las preguntas se hacen en español** aunque el documento esté en inglés. Eso también se está
midiendo: si el modelo de embeddings multilingüe encuentra el fragmento correcto cruzando idiomas.

**Regla de la ronda: una pregunta, una respuesta, se anota.** Nada de reformular hasta que
acierte — en producción el cliente pregunta una vez y se queda con lo que salga.

---

## Preguntas con respuesta en el documento

| # | Pregunta | Buscar en | Respuesta correcta (del PDF) | Respuesta del RAG | ¿OK? |
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

## Preguntas de control — la respuesta correcta es que se calle

| # | Pregunta | Respuesta esperada | Respuesta del RAG | ¿OK? |
|---|---|---|---|---|
| 17 | ¿Cuál es la multa máxima bajo el GDPR? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |
| 18 | ¿Qué dice esta norma sobre el uso de inteligencia artificial o modelos de lenguaje? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |
| 19 | ¿Cuánto cuesta obtener la certificación oficial HIPAA? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |
| 20 | ¿Qué obligaciones aplican a un laboratorio clínico en Colombia? | "No encontré eso en los documentos cargados." |No encontre eso en los documentos cargados. | |

---

## Resultado

**Criterio de calificación, fijado antes de contar:** una respuesta cuenta como acierto si un
administrador de clínica puede actuar con ella sin equivocarse. Incompleta ≠ incorrecta, pero
tampoco es acierto: se cuenta aparte.

| Métrica | Valor |
|---|---|
| ✅ Completas y correctas (de 16) | **7** — preguntas 1, 3, 4, 5, 6, 8, 10 |
| ⚠️ Correctas pero incompletas (de 16) | **7** — preguntas 7, 9, 11, 12, 13, 15, 16 |
| ❌ Con dato erróneo | **1** — pregunta 2 |
| ❌ No respondió (fallo del sistema) | **1** — pregunta 14 |
| ✅ Preguntas de control (de 4) | **4 de 4** |
| **Respuestas inventadas** | **0** |

**Dos números, según qué tan estricto seas:**

| Criterio | Resultado |
|---|---|
| Estricto (solo respuestas completas) | **11 / 20 — 55%** |
| Permisivo (completas + incompletas sin error) | **18 / 20 — 90%** |

Esa distancia entre 55% y 90% **es el hallazgo**, no un problema del método: el sistema casi
nunca miente, pero muy seguido se queda corto. Para una clínica, una respuesta a medias que
suena completa es más peligrosa que uno que dice "no sé".

### Lo que salió bien

**Cero alucinaciones en 20 preguntas.** Las 4 de control respondieron exactamente *"No encontré
eso en los documentos cargados"*, incluida la trampa de la certificación HIPAA que no existe.
Ninguna respuesta de las otras 16 afirma algo falso — las que fallan, fallan por omisión.

**Cruce de idiomas confirmado.** Todas las preguntas se hicieron en español sobre un documento
en inglés. La recuperación funcionó en los 20 casos: BGE-M3 multilingüe cumple.

### El error de la pregunta 2 — el más sutil de todos

El RAG resumió *"a partir de 500 individuos"*, pero la cita textual que él mismo trae dice
**"more than 500 residents of a State or jurisdiction"**.

*Más de 500* excluye el caso de exactamente 500. *A partir de 500* lo incluye. Una brecha de
exactamente 500 personas **no** obliga a avisar a los medios, y el resumen dice que sí.

El sistema recuperó el texto correcto y se equivocó al resumirlo. Ese es el tipo de error que
nadie detecta leyendo la respuesta, solo comparándola con la fuente — que es exactamente para
lo que existe esta evaluación.

### Las 7 incompletas tienen una sola causa

| # | Qué faltó |
|---|---|
| 7 | Las exclusiones y la presunción de brecha (dio solo la definición) |
| 9 | La prórroga de 30 días |
| 11 | Que el individuo puede pedir un período menor |
| 12 | El cuarto nivel de multa — negligencia deliberada **no** corregida, el más grave |
| 13 | Los factores (d) y (e) de cinco |
| 15 | Cuatro de los ocho elementos, incluido el encabezado literal obligatorio |
| 16 | Dos de los seis casos |

**Todas son listas cortadas.** El sistema encuentra dónde empieza la enumeración y entrega los
primeros elementos. Es el mismo fallo diagnosticado en la pregunta 14, solo que ahí el corte fue
tan temprano que el agente ni pudo responder.

**No es el modelo: es el chunking.** Fragmentos de 1000 caracteres parten las listas largas, y
ninguna búsqueda recupera lo que quedó separado de su encabezado.

### Latencia y fiabilidad medidas

| Métrica | Valor |
|---|---|
| Mediana | 16 s |
| Promedio | 18 s |
| Peor caso completado | 262 s |
| Fallo por timeout | 604 s |
| Consultas que fallaron y hubo que repetir | 3 de 23 |

### Las tres correcciones que salen de esto

1. **`chunkSize` de 1000 → 2000, o partición semántica.** Ataca la causa de las 7 incompletas y
   del fallo de la 14. Obliga a reindexar los 577 fragmentos (~8 min).
2. **`reasoning_effort: low`.** Responder con fragmentos ya recuperados no es una tarea de
   razonamiento; el modelo estaba pensando un problema ya resuelto.
3. **Timeout de 30–60 s con mensaje al usuario.** Hoy el corte está en 604 s, que para un chat
   equivale a no tener ninguno.

**El antes y el después de aplicar la nº 1 sobre estas mismas 20 preguntas es la medición que
hace que este proyecto valga.**

---

## Preguntas a vigilar — las que tienen trampa adentro

Anotadas antes de medir, para no racionalizar después.

- **La 3** tiene **dos casos** (≥500 y <500). Lo más probable es que responda solo el primero. Eso
  no es una respuesta equivocada: es una **incompleta que parece completa**, y deja a un
  administrador creyendo que no debe reportar nada cuando tiene una obligación anual pendiente.
- **La 5** no es "6 años" a secas. El *"la que sea posterior"* cambia la cuenta: una política
  vigente diez años se guarda 6 años **desde que dejó de usarse**.
- **La 7** tiene tres capas: definición, exclusiones y presunción. La que importa es la tercera —
  invierte la carga de la prueba.
- **La 9 contra la 10.** Acceso son 30 días, enmienda son 60. Dos derechos parecidos con plazos
  distintos: si los confunde, es que recuperó el fragmento equivocado, y la respuesta errada se
  ve igual de segura que la correcta.
- **La 11** son 6 años **de un subconjunto**: tratamiento, pago y operaciones están excluidos.
- **La 15** es el mejor detector de alucinación de las 16: el encabezado es **texto literal
  obligatorio**. Un modelo que responda de memoria lo va a parafrasear.

---

## Nota sobre la vigencia del corpus

Este texto tiene enmiendas **hasta marzo de 2013**. Los montos de multa de § 160.404 se ajustan
por inflación cada año, así que las cifras que responda el sistema son las de 2013 y no las
vigentes hoy.

**Eso no es un fallo del RAG: es un fallo del corpus.** Y es justo la limitación que hay que
decirle a un cliente antes de que la descubra solo — un RAG es tan actual como los documentos
que le cargaron, y mantenerlos al día es parte del servicio, no un extra.

**Consecuencia práctica:** las respuestas de la pregunta 12 no se cuentan como fallo del sistema
si coinciden con el documento. Se anotan aquí.
