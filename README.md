***English** · [Español](README.es.md)*

# Private RAG — measured, not demoed

A retrieval-augmented generation system running entirely on my own server, built to answer
questions about regulatory documents **without the documents ever leaving the machine**.

The point of this repo is not that it works. It's that I measured how well it works, found
where it breaks, and can prove which fix was worth doing — including the one I got wrong.

**Stack:** PostgreSQL 17 + pgvector · Ollama with BGE-M3 (local, CPU-only) · n8n ·
`gpt-5-mini` for drafting
**Server:** Hetzner CX33 — 4 vCPU, 8 GB RAM, no GPU · ~$9/month
**Corpus:** HIPAA Administrative Simplification, 45 CFR Parts 160, 162 and 164 — 148 sections,
pulled from the eCFR API, current as of 2026-08-06

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

## The finding that reshaped the project

The first version of this system indexed a **PDF**: 115 pages, 577 chunks, cut every 1000
characters. Seven of sixteen answers came back incomplete because enumerated lists were split
across chunk boundaries.

The obvious diagnosis was "fix the chunking." **It was the wrong diagnosis.**

The regulation is published by the eCFR as a **public API with no key**, and it returns every
section as its own `<DIV8 TYPE="SECTION">` with its number and official citation as attributes.
The structure I was about to reconstruct with a regex **was in the source all along**.

```
3 API calls  →  148 Markdown files, one per section  →  653 chunks,
                each carrying its §, its official citation and its retrieval date
```

**The bottleneck was never the chunking strategy. It was choosing the wrong input format.**
A PDF is a photograph of a document; the XML is the document. Every hour spent tuning chunk size
was spent reconstructing structure that a `curl` would have handed over intact.

Two consequences fell out of it for free:

- **Provenance travels with each fragment.** Every chunk carries `section`, `citation`, `source`
  URL and `retrieved` date. That's what makes an answer auditable instead of merely plausible.
- **The corpus is current.** The PDF was amended through March 2013. The API reports its own
  effective date, so the corpus can never silently go stale.

### And the corpus really was stale

The eCFR also exposes a **versions endpoint**. Querying it for the 17 sections behind the
evaluation returned **33 amendment records, every one of them later than the PDF's date**.

Most cluster on a single 2016 date and look like a technical amendment. Three do not:
`160.103`, `164.502` and `164.520` carry 2024 and 2026 amendments — one of them from **two
months ago**.

Verified by hand: the penalty amounts in § 160.404 and the five notification elements in
§ 164.404 are unchanged, so those answers still hold. **The point is not that the answers were
wrong. It's that I could not have known without checking** — and a two-minute API call replaced
an afternoon of re-verification.

For a customer, this is the service, not a footnote: **their documents age too.**

---

## Results

20 questions with answers verified by hand against the source — 16 with a known answer, and
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

**Read these as a paired comparison, not as absolute quality.** With n=20 a single proportion
carries roughly ±19 points of error; what the same 20 questions across two configurations *can*
support is the direction and size of the change, because the hard questions are hard in both runs.

**Latency**, across 23 runs: median 16 s · mean 18 s · worst completed 262 s · one timeout at
604 s.

**Indexing:** 653 chunks in about 9 minutes on 4 vCPU with no GPU. Paid once.

> **Measurement of the restructured corpus is in progress.** The two columns above are the PDF
> corpus. The third number is not published until the same 20 questions have been run against
> the section-based corpus and graded by the same strict rule.

---

## What the evaluation found

**Zero hallucinations across 20 questions.** All four control questions were answered with *"I
didn't find that in the loaded documents"* — including a trap asking the price of an official
HIPAA certification, which does not exist. For a healthcare buyer, this is the number that
matters: a system that stays quiet is auditable, one that improvises is a liability.

**Raising `topK` from 5 to 20 fixed four answers and broke one.** Question 16 went from
partially correct to *"I didn't find that"* — with twenty fragments in context, the signal got
buried in noise.

That result has a name I found only afterwards: **"Lost in the Middle."** Production guidance
puts it plainly — *don't return more than 10 documents without reranking, or the model ignores
what sits in the middle of the context*. Raising `topK` bought recall and paid for it in
precision. **It was not a fix; it was a trade.**

**One error no reader would catch.** Asked at what number of affected individuals the media must
be notified, the system answered *"from 500"* while quoting the source text it had retrieved:
*"more than 500 residents"*. A breach affecting exactly 500 people does **not** trigger media
notification. Retrieval was correct; the summary was wrong.

**Retrieval failures and generation failures need opposite fixes.** Question 14 failed because
the fragments holding the answer never reached the model. Question 2 failed with the correct text
in hand. Chunking fixes the first; prompting fixes the second. Looking only at the final answer,
both read as "incomplete".

**And now the two can be told apart.** Reading a single execution's retrieval step showed that on
the restructured corpus, question 14 recovered elements (A)–(D) at rank 1 and element (E) at
rank 15 — but the answer also included a requirement from **§ 164.410**, a different obligation
belonging to a different party. Retrieval did its job; the drafter mixed two sections.

**That error was invisible before.** On the PDF corpus every fragment cited the same document
title. Now the citation gives it away mid-sentence. **Metadata didn't fix the failure — it made
it measurable.**

---

## Method: measure before you build

Four expensive fixes were proposed during this build. **Three were wrong, and measuring is what
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

**"Write a preprocessor to extract the § from each chunk."**
Two hours of parsing, made unnecessary by one question nobody had asked: *where did this PDF come
from?* The source publishes the same text with the structure already in it.

The pattern: **the failures that cost you are not the ones that crash.** A parameter set wrong
announces itself — the system errors out and tells you. A confident diagnosis doesn't. It reads
well, it sounds finished, and it sends you off to build the wrong thing for an afternoon.

Every one of those was caught the same way: by asking whether a claim had been verified or was
being asserted from memory, and running the cheap experiment before authorizing the expensive
one.

---

## Known limitations

Stated because a result without its limits isn't a result.

- **20 questions, so the absolute score carries ±19 points.** Practitioner guidance puts a
  starting golden dataset at [50–100](https://qdrant.tech/blog/rag-evaluation-guide/) — and even
  50 only narrows it to ±12. Treat the paired comparison as the result; treat the percentage as
  an order of magnitude.
- **653 chunks.** Asking for 20 is 3% of this corpus; against 100,000 chunks it would be 0.02%.
  **The `topK` fix does not scale** — past a certain corpus size the answer is reranking.
- **Vector search only, no hybrid.** Embeddings match by meaning, not by exact string — they are
  weak at finding a literal `164.404`. Keyword search (BM25) is not, and production systems run
  both. In Anthropic's measurement, adding BM25 dropped retrieval failure from 3.7% to 2.9%.
- **No vector index on the table** — only the primary key. Every search scans all 653 chunks one
  by one. Invisible at this corpus size; not at a hundred thousand.
- **Two of twenty retrieved slots were section headings** — a single line each, contributing
  nothing. Roughly 10% of the context window wasted.
- **§ 160.404 points to 45 CFR Part 102 for inflation-adjusted penalty amounts, and Part 102 is
  not in the corpus.** The regulation cross-references outside its own parts; answering penalty
  questions completely would require loading it.

---

## What's next

1. **Reranking** — the one change that addresses both open failures at once: the noise that broke
   question 16, and the § 164.410 fragment that reached rank 2. `bge-reranker-v2-m3` runs on the
   same Ollama instance. The cost is latency, on CPU with no GPU, and **no source I found gives a
   measured figure for that** — so it gets measured here.
2. **Hybrid search (BM25 + vector)** with Reciprocal Rank Fusion. A GIN index over `tsvector`
   alongside the vector one — no new infrastructure.
3. **Fix question 2 in the prompt** — quote before summarizing. Neither chunking nor `topK`
   touches a generation failure.

---

## Repository layout

```
docker-compose.yml              Postgres + pgvector and Ollama, no published ports
corpus/descargar-corpus.ps1     Pulls 45 CFR 160/162/164 from the eCFR API → one .md per section
corpus/cargar-en-n8n.ps1        Posts each section to an authenticated n8n webhook for indexing
evaluacion/preguntas.md         The 20 questions, hand-verified answers, and results
evaluacion/investigacion-*      Sourced research behind the chunking and production decisions
```

The corpus itself is not versioned — `descargar-corpus.ps1` regenerates it in about ten seconds,
and it would be stale the moment it was committed.

**The evaluation documents are written in Spanish on purpose.** The questions are asked in
Spanish against an English regulation: that cross-language gap is part of what is being measured,
so translating them would erase the experiment.

Secrets live in a `.env` that is not versioned. The database publishes no port. The ingestion
webhook requires a header token.
