***English** · [Español](README.es.md)*

# Private RAG — measured, not demoed

A retrieval-augmented generation system running entirely on my own server, answering questions
about US healthcare regulation **without the documents ever leaving the machine**.

The point of this repo is not that it works. It's that I measured how well it works, found where
it breaks, and can prove which fix was worth doing — including the ones I got wrong.

**Stack:** PostgreSQL 17 + pgvector · Ollama with BGE-M3 (local, CPU-only) · n8n · `gpt-5-mini`
**Server:** Hetzner CX33 — 4 vCPU, 8 GB RAM, no GPU · ~$9/month
**Corpus:** HIPAA, 45 CFR Parts 160/162/164 — 148 sections from the eCFR API, current as of 2026-08-06

---

## Results

20 questions, answers verified by hand against the source. 16 have a known answer; **4 are
controls whose correct answer is for the system to say it doesn't know.**

| | PDF, topK 5 | PDF, topK 20 | **Section corpus** |
|---|---|---|---|
| Complete and correct (of 16) | 7 | 11 | **12** |
| Failures (of 16) | 9 | 5 | **4** |
| False negative (silent while holding the answer) | 0 | **1** | **0** |
| Control questions passed | **4 / 4** | **4 / 4** | **4 / 4** |
| **Hallucinations** | **0** | **0** | **0** |
| **Strict score** | 11/20 — 55% | 15/20 — 75% | **16/20 — 80%** |

**That +5 is not a result.** With n=20 the score carries ±18 points, and 75→80 is a single
question. Reporting it as "improved to 80%" would be reporting noise.

**Here is the result:**

| Raising `topK` from 5 to 20 | fixed 4 · **broke 1** |
| Restructuring the corpus | fixed 3, plus recovered a question that used to time out · **broke 0** |

The first change was a trade. The second wasn't. That distinction is only visible because the same
20 questions ran against both.

---

## What it actually answers

![Two questions in one session: the first returns six cases with its citation, the second refuses because GDPR is not in the corpus](chat-example.png)

Two questions, one session, nothing staged.

**The first** asks in Spanish where the *minimum necessary* standard does not apply, against an
English regulation. It comes back with all six cases and the citation — `45 CFR 164.502` — which is
a section you can open and check.

**The second** asks for the maximum GDPR fine. GDPR is not in this corpus. The answer is the exact
refusal string, and **that is the half a clinic is buying**: a system that stays quiet is
auditable, one that improvises is a liability.

**The right-hand panel is the part worth reading twice.** It shows what the prose can only claim:

| `Success in 17.729s` | Real latency, on 4 vCPU with no GPU |
| `~5811 Tokens` | What one answer costs |
| `20 items` into the Tool connection | The 20 fragments actually reaching the model |
| `1024 items` on Embeddings | BGE-M3's signature — computed on the same box that stores them |
| The execution tree | It searched **before** it wrote. That's rule 1 of the prompt, enforced |

---

## The shape

```
INGEST — paid once, ~9 min on 4 vCPU with no GPU

  eCFR API ──→ 148 Markdown files ──→ one POST per section ──→ n8n
   3 calls        one per §            authenticated webhook      │
                                                                  │
                                        split 1000 / 150 overlap ─┤
                                       BGE-M3 embeddings, local ──┤
                                                                  ↓
                                              PostgreSQL + pgvector
                                              653 fragments, each carrying
                                              its §, its official citation
                                              and the date it was retrieved


ASK — median 16 s

  question in Spanish ──→ BGE-M3 ──→ 20 nearest fragments ──→ gpt-5-mini
   against English text   same model    from pgvector           writes
                          as ingest                                │
                                                                   │
                              answer + verifiable citation ────────┤
                        or "No encontré eso en los documentos" ────┘
```

**Nothing crosses the boundary in the middle.** The document is turned into vectors on the same box
that stores them; only the 20 retrieved fragments ever leave the server.

---

## Run it

```bash
docker compose up -d                                  # Postgres + pgvector, Ollama
docker compose exec ollama ollama pull bge-m3         # embeddings model, 1.2 GB

pwsh corpus/descargar-corpus.ps1                      # 3 API calls → 148 .md files
```

Import both workflows from [`workflows/`](workflows/) into n8n. Each node carries a note explaining
what it does and why, and every field you have to change is marked `>>> REPLACE` — three
credentials (Postgres, Ollama, header auth) and nothing else.

```powershell
$env:RAG_N8N   = "https://your-n8n.example.com"
$env:RAG_TOKEN = "<the header-auth token you created>"
pwsh corpus/cargar-en-n8n.ps1                         # 148 POSTs, ~9 min on 4 vCPU
```

Neither Postgres nor Ollama publishes a port. The ingestion webhook requires a header token.

---

## The architecture decision that matters

**Embeddings run locally. Only the retrieved fragments leave the server.**

That is the whole pitch for a clinic or a lab: the document itself is never uploaded anywhere.
BGE-M3 turns it into vectors on the same box that stores them.

A second decision that costs nothing and prevents an outage: **this stack has its own compose
file**, separate from the n8n instance running a client's bot. Bringing the RAG down for
maintenance cannot take a customer offline.

---

## The finding that reshaped the project

The first version indexed a **PDF**: 115 pages, 577 chunks, cut every 1000 characters. Seven of
sixteen answers came back incomplete because enumerated lists were split across chunk boundaries.

The obvious diagnosis was "fix the chunking." **It was the wrong diagnosis.**

The regulation is published by the eCFR as a **public API with no key**, returning every section as
its own `<DIV8 TYPE="SECTION">` with its number and official citation as attributes. The structure
I was about to reconstruct with a regex **was in the source all along**.

```
3 API calls  →  148 Markdown files, one per section  →  653 chunks,
                each carrying its §, its official citation and its retrieval date
```

**The bottleneck was never the chunking strategy. It was choosing the wrong input format.**
A PDF is a photograph of a document; the XML is the document.

Two consequences fell out for free:

- **Provenance travels with each fragment** — `section`, `citation`, `source` URL, `retrieved` date.
  That is what makes an answer auditable instead of merely plausible.
- **The corpus is current.** The PDF was amended through March 2013. The API reports its own
  effective date, so the corpus cannot silently go stale.

### And the corpus really was stale

The eCFR also exposes a **versions endpoint**. Querying it for the 17 sections behind the
evaluation returned **33 amendment records, every one later than the PDF's date**. Three sections
carry 2024 and 2026 amendments — one from **two months ago**.

Verified by hand: the penalty amounts in § 160.404 and the five notification elements in § 164.404
are unchanged, so those answers still hold. **The point is not that the answers were wrong — it's
that I could not have known without checking**, and a two-minute API call replaced an afternoon of
re-verification.

For a customer this is the service, not a footnote: **their documents age too.**

---

## What the evaluation found

**Zero hallucinations across 20 questions, in all three runs.** All four controls answered *"I
didn't find that in the loaded documents"* every time.

**Raising `topK` from 5 to 20 fixed four answers and broke one.** Question 16 went from partially
correct to *"I didn't find that"* — with twenty fragments in context, the signal got buried.

That result has a name I found only afterwards: **"Lost in the Middle."** Production guidance puts
it plainly — *don't return more than 10 documents without reranking, or the model ignores what sits
in the middle of the context*. Raising `topK` bought recall and paid for it in precision.

**One error no reader would catch.** Asked at what number of affected individuals the media must be
notified, the system answered *"from 500"* while quoting the text it had retrieved: *"more than 500
residents"*. A breach affecting exactly 500 people does **not** trigger media notification.
Retrieval was correct; the summary was wrong. *(Fixed on the section corpus.)*

**Retrieval failures and generation failures need opposite fixes** — and now they can be told
apart, by reading what the retrieval step actually returned.

**Two of the four remaining failures are wrong citations**, and they are not new failures: they are
failures that used to be invisible. A citation pointing at a 115-page document can never be wrong.
One pointing at `45 CFR 164.530` can, and that one is — the Security Rule safeguards live in
§§ 164.308, 164.310 and 164.312.

**The other two are rank dilution, and it was measured.** Asked to define *business associate*, the
system returned an answer missing the core clause. Reading the retrieval step showed why: **only 3
of the 20 retrieved fragments came from § 160.103**, the section that defines the term. The other
17 came from seven sections that *mention* business associates without *defining* them.

The term appears throughout the regulation, so semantic search returned the topic and left three
slots out of twenty to the one section that answers. **That is the textbook case for hybrid search
and reranking.**

**Two hypotheses died mid-run.** First: *"list questions fail, single-fact questions pass"* — killed
by Q12, a four-tier penalty schedule answered completely. Second: *"it fails when the section is
huge"* — killed by Q16, perfect out of one of the largest sections. The third hypothesis, rank
dilution by term popularity, fits all twenty cases and is **stated as a hypothesis**, to be tested
by the reranking work rather than announced as a conclusion.

**And the methodological warning that outranks the score.** Question 14 was run twice under an
identical configuration. The first run returned the five required elements **plus one belonging to
§ 164.410**. The second returned the five clean. Nothing changed between them. **The model is not
deterministic**, so this 80% carries two sources of noise — sampling and the model itself.

---

## Method: measure before you build

Four expensive fixes were proposed during this build. **Three were wrong, and measuring is what
proved it.**

**"The chunks are cut mid-list — reindex with a different strategy."**
Plausible, evidence-backed, and it would have cost an afternoon. A one-minute experiment — raising
`topK` — showed the missing fragments *existed*, just ranked below the cutoff. The diagnosis had
confused *"didn't arrive"* with *"doesn't exist"*.

**"Raise `chunkSize` from 1000 to 2000."**
The most thorough study on the subject ([Zhou et al., 2026](https://arxiv.org/abs/2602.16974))
finds chunk size *"correlates weakly with in-corpus effectiveness"*. Size is not the lever —
**where you cut is**.

**"Cap `maxTokens` to control latency."**
`maxTokens` truncates the output; it treats the symptom. For GPT-5-class models the parameter that
matters is `reasoning_effort` — an engineer running
[Microsoft's own RAG evaluation](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/gpt-5-will-it-rag/4442676)
found `minimal` never spent reasoning tokens and still produced high-quality answers, and suggests
RAG answering may simply be a non-reasoning task. **He says outright that he did not test the
alternative**, so this is a lead, not a finding — which is exactly how it should have been cited the
first time. *(See the [source audit](evaluacion/investigacion-chunking.md#source-audit--what-survived-verification-and-what-didnt).)*

**"Write a preprocessor to extract the § from each chunk."**
Two hours of parsing, made unnecessary by one question nobody had asked: *where did this PDF come
from?*

The pattern: **the failures that cost you are not the ones that crash.** A parameter set wrong
announces itself. A confident diagnosis doesn't — it reads well, sounds finished, and sends you off
to build the wrong thing for an afternoon.

### Who proposed them

Those four fixes were proposed by the AI assistant this was built with, in Claude Code. Three were
wrong — and **not one of them was caught by the assistant reviewing its own work.** Each was caught
by the same human question: *was this verified, or is it being asserted from memory?*

That question is the method. The tooling is replaceable; the habit of demanding evidence before
authorizing an afternoon of work is not.

---

## Known limitations

Stated because a result without its limits isn't a result.

- **20 questions, so the absolute score carries ±18 points.** No practitioner guide I found puts
  the floor below 50 — [QASkills](https://qaskills.sh/blog/golden-dataset-llm-evaluation-guide) says
  50–100 as minimum viable, [Braintrust](https://www.braintrust.dev/articles/what-is-rag-evaluation)
  50–200, and [Microsoft](https://medium.com/data-science-at-microsoft/the-path-to-a-golden-dataset-or-how-to-evaluate-your-rag-045e23d1f13f)
  *"certainly not less than 100"*. Even 50 only narrows the margin to ±12. The paired comparison is
  the result; the percentage is an order of magnitude.
- **One run per question.** Q14 proved the model gives different answers to identical inputs.
- **653 chunks.** Asking for 20 is 3% of this corpus; against 100,000 it would be 0.02%. **The
  `topK` fix does not scale.**
- **Vector search only, no hybrid.** Embeddings match by meaning, not exact string — weak at finding
  a literal `164.404`. In Anthropic's measurement, adding BM25 dropped retrieval failure from 3.7%
  to 2.9%. Read that number as a ceiling, not a forecast: **they used BM25 and this box cannot** —
  see the correction in *What's next*.
- **No vector index on the table** — only the primary key. Every search scans all 653 chunks.
- **Two of twenty retrieved slots were section headings** — one line each. ~10% of context wasted.
- **§ 160.404 points to 45 CFR Part 102 for inflation-adjusted penalties, and Part 102 is not in the
  corpus.** The regulation cross-references outside its own parts.

---

## What's next

1. **Hybrid search (`ts_rank_cd` + vector) with Reciprocal Rank Fusion.** A GIN index over
   `to_tsvector('english', text)` beside the vector one — no new service, no new container. Both
   searches and the fusion fit in **one SQL statement**: that is the shape of
   [pgvector's own example](https://github.com/pgvector/pgvector-python/blob/master/examples/hybrid_search/rrf.py),
   two CTEs joined with `FULL OUTER JOIN` and scored `1.0 / (k + rank)` with `k = 60` — a constant
   that comes from Cormack et al. (2009) and that the example's users recommend testing rather than
   inheriting. Take 20 candidates from each side, fuse, return 10.

   Optionally **weighted toward the lexical side**, following
   [ParadeDB](https://www.paradedb.com/blog/hybrid-search-in-postgresql-the-missing-manual): their
   70/30 split *"works well for technical documentation where users often search for specific terms,
   function names, or error messages."* A corpus of `§ 164.404` and `(c)(1)(A)` is exactly that, and
   it is where vector-only search is weakest.

   **Correction, 9 Aug:** this section previously said *BM25*. It was wrong. BM25 needs ParadeDB's
   `pg_search` extension, which this image does not carry — what Postgres ships natively is
   `ts_rank_cd`, which scores each document in isolation and has no corpus-wide term statistics.
   ParadeDB argues that gap matters at scale. **Untested assumption:** at 653 fragments, where
   `164.404` appears in two or three of them, the `@@` filter should do most of the work before
   ranking matters. That is a guess, and the evaluation will say.

   **A caveat this corpus forces:** the documents are English and the questions are Spanish. Lexical
   search does not cross languages, so this fix should move the identifier questions and almost
   nothing else. If it repairs 2 or 3 of the 20, it worked.

2. **Fix the two citation failures in the prompt.** Neither chunking nor `topK` touches a generation
   failure.

3. **Reranking, and not on this box.** `bge-reranker-v2-m3` would address both open failure types at
   once, but **Ollama cannot serve reranking models.** Verified 9 Aug: an Ollama maintainer states it
   plainly in [issue #10467](https://github.com/ollama/ollama/issues/10467), closed as a duplicate of
   [#3368](https://github.com/ollama/ollama/issues/3368), the feature request open since March 2024.
   The trap worth naming: you *can* pull a reranker into Ollama and call `/api/embed`, and it returns
   numbers — the embedding layer, not the classification head that does the ranking. **Plausible
   output, silently wrong.** n8n's only reranker node is Cohere, which would send the retrieved
   fragments off the machine and break the one promise this project makes. So this gets tested on a
   GPU box, which is also the number a client with a GPU would actually get.

   **Correction, 9 Aug:** this section previously said the reranker *"runs on the same Ollama
   instance."* It does not. That line was written from assumption, not verification.

---

## Repository layout

```
docker-compose.yml              Postgres + pgvector and Ollama, no published ports
corpus/descargar-corpus.ps1     Pulls 45 CFR 160/162/164 from the eCFR API → one .md per section
corpus/cargar-en-n8n.ps1        Posts each section to an authenticated n8n webhook for indexing
workflows/cargar-secciones.json The ingestion workflow. Import into n8n.
workflows/preguntar.json        The query workflow: agent, retriever and local embeddings.
workflows/system-prompt.md      The five prompt rules, and what each one was measured to do
sql/busqueda-hibrida.sql        Hybrid retrieval in one statement, with why each choice was made
evaluacion/preguntas.md         The 20 questions, hand-verified answers, and all three rounds
evaluacion/investigacion-*      Sourced research behind the chunking and production decisions
```

The two workflow files carry no credentials — only the fields you must fill, marked `>>> REPLACE`.
Node names are in Spanish because I am the one reading them at 3am when something stops.

**`system-prompt.md` is worth opening even if you never run this.** It's five rules, and what
matters is the measurement attached to each: which one produced zero hallucinations across sixty
answers, which one did nothing for two rounds, and **which one visibly failed**.

The corpus itself is not versioned — `descargar-corpus.ps1` regenerates it in about ten seconds,
and it would be stale the moment it was committed.

**The evaluation documents are in Spanish on purpose.** The questions are asked in Spanish against
an English regulation; that gap is part of what is measured, so translating them would erase the
experiment.

Secrets live in a `.env` that is not versioned.
