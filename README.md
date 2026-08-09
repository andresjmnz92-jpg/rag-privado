***English** · [Español](README.es.md)*

# Private RAG — measured, not demoed

A retrieval-augmented generation system running entirely on my own server, built to answer
questions about regulatory documents **without the documents ever leaving the machine**.

The point of this repo is not that it works. It's that I measured how well it works, found
where it breaks, and can prove which fix was worth doing.

**Stack:** PostgreSQL 17 + pgvector · Ollama with BGE-M3 (local, CPU-only) · n8n ·
`gpt-5-mini` for drafting
**Server:** Hetzner CX33 — 4 vCPU, 8 GB RAM, no GPU · ~$9/month
**Corpus:** HIPAA Administrative Simplification, 45 CFR Parts 160, 162 and 164 — 115 pages

---

## The architecture decision that matters

**Embeddings run locally. Only the retrieved fragments leave the server.**

That is the whole pitch for a clinic or a lab: the document itself is never uploaded anywhere.
BGE-M3 turns it into vectors on the same box that stores them. Postgres and Ollama publish no
ports — they are reachable only from inside the Docker network.

A second decision that costs nothing and prevents an outage: **this stack has its own compose
file**, separate from the n8n instance running a client's bot. Bringing the RAG down for
maintenance cannot take a customer offline.

**Cross-language retrieval works.** Every question below was asked in Spanish against an English
document. BGE-M3 is multilingual, and retrieval succeeded in all 20 cases.

---

## Results

20 questions with answers verified by hand against the source PDF — 16 with a known answer, and
**4 control questions whose correct answer is for the system to say it doesn't know**.

| | topK = 5 | topK = 20 |
|---|---|---|
| Complete and correct | 7 | **11** |
| Incomplete but not wrong | 7 | 3 |
| Contained a wrong figure | 1 | 1 |
| False negative (stayed silent while holding the answer) | 0 | **1** |
| Control questions passed | **4 / 4** | **4 / 4** |
| **Hallucinations** | **0** | **0** |
| **Strict score** | **11/20 — 55%** | **15/20 — 75%** |

**Latency**, across 23 runs: median 16 s · mean 18 s · worst completed 262 s · one timeout at
604 s.

**Indexing:** 577 chunks in 8 min 8 s on 4 vCPU with no GPU — about 14 pages per minute. Paid
once.

---

## What the evaluation found

**Zero hallucinations across 20 questions.** All four control questions were answered with *"I
didn't find that in the loaded documents"* — including a trap asking the price of an official
HIPAA certification, which does not exist. For a healthcare buyer, this is the number that
matters: a system that stays quiet is auditable, one that improvises is a liability.

**Raising `topK` from 5 to 20 fixed four answers and broke one.** Question 16 went from
partially correct to *"I didn't find that"* — with twenty fragments in context, the signal got
buried in noise. **The optimum is at neither extreme**, and that only shows up if you re-run the
questions that were already passing.

**One error no reader would catch.** Asked at what number of affected individuals the media must
be notified, the system answered *"from 500"* while quoting the source text it had retrieved:
*"more than 500 residents"*. A breach affecting exactly 500 people does **not** trigger media
notification. Retrieval was correct; the summary was wrong. That class of error is invisible
unless you compare every answer against the source — which is what the evaluation is for.

**Retrieval failures and generation failures need opposite fixes.** Question 14 failed because
the fragments holding the answer never reached the model. Question 2 failed with the correct text
in hand. Chunking fixes the first; prompting fixes the second. Looking only at the final answer,
both read as "incomplete".

---

## Method: measure before you build

Three expensive fixes were proposed during this build. **Two were wrong, and measuring is what
proved it.**

**"The chunks are cut mid-list — reindex with a different strategy."**
Plausible, evidence-backed, and it would have cost an afternoon re-chunking 577 fragments. A
one-minute experiment — raising `topK` — showed the missing fragments *existed*; they were just
ranked below the cutoff. The diagnosis had confused *"didn't arrive"* with *"doesn't exist"*.

**"Raise `chunkSize` from 1000 to 2000."**
The most thorough study on the subject ([Zhou et al., 2026](https://arxiv.org/abs/2602.16974))
finds chunk size *"correlates weakly with in-corpus effectiveness"*. Size is not the lever —
**where you cut is**.

**"Cap `maxTokens` to control latency."**
`maxTokens` truncates the output; it treats the symptom. For GPT-5-class models the parameter
that matters is `reasoning_effort`, because *"RAG answering is a non-reasoning task"*
([Microsoft](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/gpt-5-will-it-rag/4442676)).
The model was reasoning about a problem retrieval had already solved.

The pattern: **the failures that cost you are not the ones that crash.** A parameter set wrong
announces itself — the system errors out and tells you. A confident diagnosis doesn't. It reads
well, it sounds finished, and it sends you off to build the wrong thing for an afternoon.

Every one of those was caught the same way: by asking whether a claim had been verified or was
being asserted from memory, and running the cheap experiment before authorizing the expensive
one.

---

## Known limitations

Stated because a result without its limits isn't a result.

- **One document, 577 chunks.** Asking for 20 is 3.5% of this corpus; against 100,000 chunks it
  would be 0.02%. **The `topK` fix does not scale** — past a certain corpus size the answer is
  reranking, not asking for more.
- **20 questions.** Practitioner guidance puts a starting golden dataset at
  [50–100](https://qdrant.tech/blog/rag-evaluation-guide/).
- **The corpus is amended through March 2013.** Civil penalty figures in § 160.404 adjust for
  inflation, so the system reports 2013 amounts. That is a corpus problem, not a retrieval
  problem — and keeping documents current is part of the service, not an extra.
- **Retrieval and generation are scored together.** The evaluation grades the final answer; it
  does not separately record whether the correct fragment made it into the context.

---

## What's next

1. **Parent-document retrieval** — the four still-failing questions each have their full answer
   inside a single section. Returning the whole section beats returning twenty loose fragments,
   and it fixes the noise problem that broke question 16.
2. **Fix question 2 in the prompt** — quote before summarizing. Neither chunking nor `topK`
   touches a generation failure.
3. **`reasoning_effort: low`** and a **30–60 s timeout** with a message to the user. The current
   cutoff is 604 s, which in a chat is the same as having none.

---

## Repository layout

```
docker-compose.yml           Postgres + pgvector and Ollama, no published ports
evaluacion/preguntas.md      The 20 questions, hand-verified answers, and results
evaluacion/investigacion-*   Sourced research behind the chunking decisions
```

Secrets live in a `.env` that is not versioned. The database publishes no port.
