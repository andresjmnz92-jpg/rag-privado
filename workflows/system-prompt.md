# The system prompt, rule by rule

This is the entire prompt driving the agent. It is five rules and it fits on a screen — the
interesting part is not the text, it's what each rule was measured to do across three evaluation
rounds of 20 questions.

```
Eres un asistente que responde UNICAMENTE con base en los documentos indexados.

Reglas:
1. Antes de responder, SIEMPRE usa la herramienta "Buscar en Documentos".
2. Responde solo con lo que aparezca en los fragmentos recuperados. No uses tu
   conocimiento propio.
3. Cita siempre de que documento salio la respuesta.
4. Si la respuesta no esta en los fragmentos, responde exactamente:
   "No encontre eso en los documentos cargados." No la inventes.
5. Responde en espanol, corto y directo.
```

*(Written without accents on purpose: it travels through a JSON field, and one mangled character
in a rule the model reads literally is not worth the risk.)*

---

## Rule 1 — always search first

Without it the agent sometimes answers directly, because it *does* know HIPAA. That is the whole
failure mode this system exists to prevent: an answer that is correct today and invented tomorrow,
with no way to tell which is which.

## Rule 2 — only what's in the fragments

**Measured: zero hallucinations across 20 questions, in all three rounds.**

The strongest evidence is a question that isn't about HIPAA at all. Asked the capital of France —
which the model obviously knows — it answered that it wasn't in the loaded documents. **Getting a
model to stay quiet about something it knows is the hard half.**

## Rule 3 — always cite

This one did nothing measurable for two rounds. Every answer cited *"Combined Regulation Text of
All Rules"* — the name of a 115-page PDF. Technically compliant, practically useless.

It only became real when the corpus was rebuilt with per-section metadata and answers started
citing `45 CFR 164.404`.

**And then something uncomfortable happened: two answers turned out to have wrong citations.**
Question 8 cited § 164.530 for the Security Rule safeguards, which live in §§ 164.308, 164.310 and
164.312.

Those were not new failures. **They were failures that had been invisible**, because a citation
pointing at an entire document can never be wrong. The rule didn't improve when the metadata
arrived — it became *checkable*.

## Rule 4 — the exact sentence

This is the one that makes the system measurable, and it is why the wording is literal instead of
"say you don't know".

Four of the twenty evaluation questions have **no answer in the corpus**, and the correct behaviour
is that exact string. A fixed sentence can be graded automatically; "I'm not sure I can help with
that" cannot.

**Result: 4/4 in every round**, including a trap asking the price of an official HIPAA
certification — which does not exist, and which a helpful model would happily invent a procedure
for.

## Rule 5 — Spanish, short, direct

**And this is the rule that visibly failed.** Question 6 came back in English.

It is the only rule with no mechanism behind it: rules 1 and 4 shape behaviour the retrieval step
can enforce, but "answer in Spanish" is a preference the model weighs against everything else in
its context — and that answer's context was 20 fragments of English legal text.

Left as is rather than reinforced, because it failed once in sixty answers and the fix would mean
adding weight to a rule that competes with the ones that matter.

---

## What the prompt does not fix

Two of the four remaining failures are **generation** failures, sitting inside a correct context:

**Question 2, rounds 1 and 2.** Asked at what number of affected individuals the media must be
notified, the answer said *"a partir de 500"* — from 500 — while quoting the retrieved text
*"more than 500 residents"*. A breach affecting exactly 500 people does not trigger media
notification. Retrieval was perfect; the summary changed the meaning.

**Questions 8 and 15, round 3.** Right content, invented citations.

Both need a prompt change — quote before summarising — and neither is touched by chunking, `topK`,
or a better corpus. That fix is in the repository's "what's next", **written before building it**
so the claim can be checked against the result.

---

## The bit worth stealing

**Rule 4 is not about honesty, it's about instrumentation.**

Any prompt can say "don't make things up". What makes this one testable is that the refusal has a
*fixed string*, so a control question either produces it exactly or it doesn't. There is no partial
credit and no judgement call.

That single design choice is what turns "the system doesn't hallucinate" from a claim into a
number.
