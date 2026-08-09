# What this RAG still needs to be a real system

*Research, 9 August 2026 · Written against the actual state of this system, not a generic RAG ·
**Every quotation fetched from its source page and checked word by word** — see the audit at the
end, including the four claims that did not survive it.*

## Short version

What's missing isn't a list of improvements: it's **three things that fail for the same reason** —
retrieval brings back the right topic and the wrong ranking — plus the instrumentation to prove it.

And one finding reorders everything else: **`topK: 20` without reranking is a documented
anti-pattern**, and it explains a result we had already measured without understanding.

---

## 1. The finding: "Lost in the Middle"

The engineering checklist from [ActiveWizards](https://activewizards.com/blog/the-production-ready-rag-pipeline-an-engineering-checklist)
has a section titled exactly that, and it is written as a question you are supposed to fail:

> *"Does your retrieval process return too many documents (e.g., >10)? LLMs often ignore
> information buried in the middle of a large context window. Are you using a **reranker** to put
> the most relevant chunks at the beginning and end of the context?"*

We set `topK: 20`. And our own measurements match the prediction, point by point:

| What we measured | What the phenomenon predicts |
|---|---|
| Going from 5 to 20 fixed 4 answers **and broke Q16** | More context lifts recall and lowers attention to the middle |
| The intruding § 164.410 fragment sat at **rank 2** | The start of the context carries weight |
| The correct element **(E)** sat at **rank 15** | The middle-to-late zone is what gets lost |

**Raising `topK` was not a fix: it was trading one problem for another.** It bought recall and paid
in precision.

Note what the checklist actually prescribes — not "return fewer documents", but **a reranker that
moves the best chunks to the beginning and end**. The ends are where the model looks.

Anthropic measured the payoff: adding reranking takes retrieval failure from **2.9% to 1.9%**
([Contextual Retrieval](https://www.anthropic.com/engineering/contextual-retrieval)).

---

## 2. Already solved, so it doesn't get rebuilt

| Piece | State |
|---|---|
| Local embeddings, documents never leave the server | Done — it's the sales argument |
| Section-structured corpus, with `§` and citation in metadata | Done, 9 Aug |
| Current corpus, dated by its own source | Done — eCFR as of 6 Aug 2026 |
| Provenance travelling with the fragment | Done — `source`, `citation`, `retrieved` |
| Golden dataset with hand-verified answers | Done — 20 questions, the expensive part |
| Control questions (hallucination rate) | Done — 4/4, result 0 |
| A prompt that forces silence when it doesn't know | Done, and measured |
| Authenticated ingestion, no published ports | Done |
| Telling retrieval failures from generation failures | Done, 9 Aug, by reading the retrieval step |

That covers about half of the ActiveWizards checklist already.

---

## 3. What's missing to fix the measured numbers

Ordered by how much it moves the result, not by difficulty.

### 3.1 Reranking — the one that addresses the cause

Retrieve 20, let a small model reorder them by real relevance, then hand the best ones to the
writer. It's a second pass, expensive but only over 20 candidates.

The model that fits this stack is **`bge-reranker-v2-m3`** — same family as BGE-M3, also
multilingual, and it runs on Ollama. *(Model choice is mine; no source recommends it for this
specific case.)*

**What it fixes, of what we already measured:** Q16, broken by noise, and the § 164.410 fragment
that reached rank 2.

**The cost:** one more call per question, on CPU with no GPU. Latency goes up, and I found no
measured figure for how much — so it gets measured here.

### 3.2 Hybrid search (BM25 + vector)

Embeddings search by meaning and are **bad at exact strings** — a literal `164.404`. BM25 is the
opposite. ActiveWizards puts it as a checklist item: *"Production systems should use hybrid search,
combining semantic (vector) search with traditional full-text or metadata filtering to improve
precision."*

[ParadeDB](https://www.paradedb.com/blog/hybrid-search-in-postgresql-the-missing-manual) explains
why you can't just merge the two naively:

> *"you can't just add BM25 scores to vector similarity scores. They're measured on completely
> different scales."*

The answer is **Reciprocal Rank Fusion**, which ignores scores and works on rankings:

```
RRF(document) = Σ 1 / (k + rank_i(document))
```

with `k` typically 60. And it works best on the top candidates from each system rather than on
whole result sets.

**The detail that applies directly here** is their weighted variant. Their 70% lexical / 30%
semantic configuration, in their words:

> *"emphasizes lexical matching over semantic similarity, which works well for technical
> documentation where users often search for specific terms, function names, or error messages."*

A corpus of `§ 164.404` and `(c)(1)(A)` is exactly that. **Our weights should favour BM25**, which
is the opposite of what a vector-only system does.

No new infrastructure: a GIN index over `tsvector` alongside the vector one, in the Postgres that
is already running.

### 3.3 The vector index

Today the table has only its primary key: every search scans all 653 fragments one by one. It
doesn't show at this size; it will.

**Honest: with 653 rows this changes no measurable number.** It gets done for what it teaches and
because it's one statement, not because it fixes anything today.

### 3.4 Merge the heading-only fragments

Two of the 20 retrieved fragments in the Q6 trace were **just the section title** — one line each.
They take a slot and contribute nothing: 10% of the context wasted. Fixed at load time by attaching
the heading to the first paragraph.

---

## 4. What's missing to be able to show it

### 4.1 Automatic evaluation with separated metrics

Today the evaluation is manual and grades **the final answer**. The standard splits what we
currently merge ([Digital Applied](https://www.digitalapplied.com/blog/rag-system-metrics-recall-precision-faithfulness-2026)):

> *"Recall at k asks whether at least one relevant chunk appeared in the top-k retrieved
> candidates; precision at k asks what fraction of the top-k chunks were actually relevant."*

Their thresholds, verbatim:

| Metric | Threshold |
|---|---|
| **Recall@10** | *"If recall@10 is below 0.85, no downstream tuning matters — the generator never saw the right context to work with."* |
| Recall@k | ≥ 0.75 |
| Precision@k | ≥ 0.45 at k=10 |
| **Faithfulness** | *"90% is the production target; below 70% the system is unsafe to ship."* |
| Faithfulness 70–90% | *"Usable with explicit 'verify the cited source' UX."* |
| **Citation accuracy** | Target **0.92** |

Faithfulness is defined precisely: *"of the factual claims made in the answer, what fraction can be
supported by the retrieved context."*

**And citation accuracy is the metric for the failure we found by hand.** Their description of what
it catches:

> *"the worst failure mode — well-cited answers where the cited chunk says something different from
> the claim."*

That is questions 8 and 15 of our evaluation, word for word. We found them by opening every
citation manually. There is a standard metric for it.

### 4.2 Getting past 50 questions

Nobody puts the floor below 50 — see the sources in
[investigacion-chunking.md](investigacion-chunking.md#5-how-serious-teams-evaluate). We're at 20.
It's the slow part and there's no shortcut: every answer comes out of the document by hand.

### 4.3 End-to-end tracing

Record per query: what was asked, which fragments came back with what score, what was answered, how
long it took, what it cost. Today that lives in n8n's executions and can be read — we did it — but
it isn't stored and can't be aggregated.

Without it, every diagnosis is manual archaeology.

---

## 5. What's missing to charge for it

Not more engineering: this is what separates a demo from something you can sell to a clinic.
Source: Tim Freestone, [Kiteworks](https://www.kiteworks.com/hipaa-compliance/healthcare-rag-hipaa-compliance-controls/).

The scope, first:

> *"HIPAA's requirements for access controls, audit trails, encryption, and business associate
> agreements apply fully to RAG workflows."*

**An audit log, and a specific one.** Not "log the queries":

> *"For RAG deployments, this means capturing who accessed which patient records, when retrieval
> occurred, what context combined into prompts, which models processed data, and who received
> responses."*

And it has to be tamper-proof: *"cryptographic signatures or write-once storage to ensure logs
can't be altered after creation."* We have none of this.

**Access control during retrieval, not after:**

> *"Data-aware filtering evaluates each retrieved document against the user's specific permissions
> before including it in the context sent to language models."*

Today any query sees everything. Fine for public regulation; not for a clinic's records.

**And the one that decides the architecture.** On third-party model APIs:

> *"Third-party model APIs reduce operational complexity but introduce dependencies on vendors
> whose terms of service may conflict with HIPAA's requirements for data use limitations and audit
> access."*

Plus a clause most people never think about:

> *"The business associate agreement should explicitly address model training, requiring that
> protected health information never contributes to model improvement without prior authorization
> and appropriate de-identification."*

**This is what pushes toward the local model.** Right now `gpt-5-mini` writes the answers, which
means retrieved fragments leave the server. With public regulation that's harmless. With PHI it
needs a signed BAA — and at that point *"everything stays on your server"* stops being marketing
and becomes the requirement.

---

## 6. What is NOT missing

As important as the list above.

- **Query caching, model routing, cost-based degradation.** Volume optimisations. With one user
  asking 20 questions they save nothing.
- **Switching vector database.** Postgres with pgvector handles millions of vectors. ParadeDB's own
  argument for staying: *"everything runs in your existing database with ACID guarantees and
  transactional consistency."*
- **Reindexing with Anthropic's Contextual Retrieval.** Best measured numbers, but it means running
  every fragment through an LLM. **Structure-based chunking already captured much of that gain** —
  evaluate it after measuring with reranking, not before.
- **Rewriting anything in Python.** Everything above fits in the n8n already running.

---

## Recommendation

**One, with its trade-off: reranking first, measured before and after with the same 20 questions.**

It attacks the cause the data already points at — good retrieval, bad selection — and it is the one
change that fixes **both open failures at once**: the noise that broke Q16 and the § 164.410
fragment at rank 2.

**The trade-off:** latency goes up. The median today is 16 s and the reranker adds a pass on CPU
with no GPU. If it climbs to 25–30 s, a live chat feels slow — and that matters for a demo. Measure
it, don't assume it.

**Order after that:** hybrid search with BM25-weighted RRF → trace logging → past 50 questions →
automated metrics. The compliance block gets built when there is a real client, not before:
building controls for data that doesn't exist yet is the definition of premature.

---

## Source audit

Every quotation above was fetched from its page on 9 August 2026 and checked word by word.
**Four claims from the first version of this document did not survive.** They are listed rather
than quietly deleted.

| Claim | Attributed to | What the page actually says |
|---|---|---|
| RAGAS targets: faithfulness **0.75**, answer relevancy **0.8**, context precision **0.7**, context recall **0.8** | Digital Applied | None of those four numbers appear. The real thresholds are stricter and differently framed: faithfulness **90%** as production target and **below 70% unsafe to ship**; **recall@10 ≥ 0.85**; citation accuracy **0.92** |
| *"Reranking is stage two, with expensive precise scoring run only over the fused top-N"* | ParadeDB | Not on the page. It does say RRF *"works best with the top candidates from each system"*, which is related but not the same claim |
| HNSW parameters **m=16, ef_construction=64** as production settings | ParadeDB | No index parameters on the page. This came from a search-result summary that blended several sources, and was never opened |
| *"Two distinct PII leak vectors: ingestion and inference"* | Kiteworks | Not on that page. It belongs to a different vendor's page that was never read |

**What this changes about the conclusion: nothing.** The three sources carrying the argument —
ActiveWizards on Lost in the Middle, ParadeDB on RRF, Kiteworks on HIPAA controls — **verified
verbatim**, and two of them turned out to say something more useful than what I had attributed to
them: the reranker moves chunks *to the beginning and end*, and the weighted-RRF configuration for
identifier-heavy corpora.

**The pattern is the same one from the chunking research:** what fell were the round, quotable
claims. What held were the ones with ugly numbers attached.

**And one method note.** The Microsoft page in the other research document returned only its title
through a plain fetch, and the first version of that audit wrote the claim off as unverifiable. A
different scraping tool recovered the full text on the first try. **A tool returning nothing is not
evidence that nothing is there.**
