# How people who do this in production actually solve it

*Research, 8 August 2026 · **Every quotation re-verified against its source page on 9 August 2026**
— see the source audit at the end, including the six claims that did not survive it.*

## Short version

The question that started this was whether to raise `chunkSize` from 1000 to 2000. **Raising it is
the patch.** Fragment size matters much less than **where you cut**. For a document like HIPAA —
numbered, hierarchical, full of explicit lists — what production teams do is **cut along the
document's own structure and return the whole parent**, not widen the window.

And there is a one-field change worth trying **today, with no reindexing**: raise `topK` from 5
to 20.

---

## 1. Fragment size is not the variable in charge

The most direct evidence against "just make it 2000" comes from the most thorough study published
on the subject, comparing structure-based, semantic and LLM-guided segmentation —
*Beyond Chunk-Then-Embed: A Comprehensive Taxonomy and Evaluation of Document Chunking Strategies
for Information Retrieval*, by Yongjie Zhou, Shuai Wang, Bevan Koopman and Guido Zuccon
([arXiv:2602.16974](https://arxiv.org/abs/2602.16974)):

> *"chunk size correlates **moderately** with in-document but **weakly** with in-corpus
> effectiveness"*

And on which method wins:

> *"simple structure-based methods **outperform LLM-guided alternatives** for in-corpus retrieval"*

Cutting along the document's own headings and sections beats methods that are far more expensive.
You don't need an LLM deciding where to cut — you need to respect the structure the author already
put there.

[Unstructured](https://unstructured.io/blog/chunking-for-rag-best-practices) makes the same point
from the practitioner side, describing what smart chunking does differently:

> *"Documents often contain a variety of elements, such as paragraphs, section headers, footers,
> lists, tables, and more, all of which contribute to their overall organization."*

Their approach *"leverages the document element types identified during partitioning to understand
the document structure, and preserves section boundaries."*

**Applied to our case:** § 164.404(c) has its five elements (A)–(E) written as one unit. Cutting
every 1000 characters split them; cutting every 2000 could split them just as easily, somewhere
else. The problem isn't the length of the scissors, it's where they land.

---

## 2. What is actually used for legal text: parent-document retrieval

This is the technique that keeps coming up once the search narrows to legal and reference
documents.

**How it works** ([ZeroEntropy](https://zeroentropy.dev/concepts/parent-document-retrieval/)):
index small fragments so search stays precise, but hand the LLM the complete parent. It separates
the unit of search from the unit of reading.

> *"For long-form prose, technical documentation, and legal text, parent-document retrieval is
> almost always a net win."*

Their recommended shape, verbatim:

> *"A common shape is 200-token chunks under 1500-2000-token parents — small enough that
> embeddings stay focused, large enough that the LLM gets the surrounding context."*

**Why it maps onto our failure exactly.** [Edtek](https://edtek.ai/kb/chunking-strategies-legal-reference-documents/)
describes our problem in one sentence:

> *"A statute's subsection (a)(2)(iv) defines a term used in subsection (a)(2)(v). Fixed chunking
> will split them mid-definition."*

Their recipe for hierarchical documents:

> *"Split on the document's own structural markers first — headings, section breaks, paragraph
> boundaries — and only fall back to fixed-size splits when no structural marker is available
> within the target chunk length."*

They rate parent-document retrieval as **"High"** precision against recursive chunking's
**"Medium-High"** — a qualitative ranking, not a measured one. **There is no benchmark number
here**, and the earlier version of this document claimed one. See the audit.

**What it costs:** almost nothing. The index is the same size because only the children are
embedded; retrieving the parent is a lookup by ID.

---

## 3. Contextual Retrieval (Anthropic): the best-measured option

This has the most solid numbers, because they were published by whoever invented the technique
([Anthropic Engineering](https://www.anthropic.com/engineering/contextual-retrieval)). An LLM
writes 50–100 tokens of context for each fragment before indexing.

Top-20-chunk retrieval failure rate:

| Configuration | Failure | Anthropic's wording |
|---|---|---|
| Base embeddings | 5.7% | — |
| + Contextual Embeddings | 3.7% | *"reduced the top-20-chunk retrieval failure rate by 35%"* |
| + Contextual BM25 | 2.9% | *"reduced the top-20-chunk retrieval failure rate by 49%"* |
| + Reranking | **1.9%** | *"reduces the top-20-chunk retrieval failure rate by 67%"* |

**Cost:** *"$1.02 per million document tokens"*, once, using prompt caching. For our 577 fragments
that's cents — but it requires reindexing every fragment through an LLM.

**The number we can use today without reindexing anything:**

> *"Passing the top-20 chunks to the model is more effective than just the top-10 or top-5."*

Ours is at **5**. That's one field, not a reindex.

---

## 4. Late chunking: promising, and barely measured

It shows up constantly in blog posts, so it's worth checking what the evidence actually is.

[Jina AI](https://jina.ai/news/late-chunking-in-long-context-embedding-models/), who proposed it,
publishes per-dataset nDCG@10 comparisons — naive versus late chunking:

| SciFact | 64.20% → 66.10% |
| NFCorpus | 23.46% → 29.98% |

Their summary claim is qualitative: *"In all cases, late chunking improved the scores compared to
the naive approach."* **They publish no averaged figure across models and datasets.**

[Weaviate](https://weaviate.io/blog/late-chunking) is blunter about the state of the evidence:

> *"late chunking is a new approach and as such there is limited data available on its performance
> in benchmarks"*

What they do report is a trend rather than a number: *"the relative uplift in performance from late
chunking was also shown to improve as the document length in characters increased."*

**Conclusion: not enough measured evidence to justify reindexing for it.** The gains reported are
real but per-dataset and uneven — 1.9 points on one, 6.5 on another — and the technique's own
advocates say the benchmark data is thin.

---

## 5. How serious teams evaluate

Our 20-question evaluation is below the standard. How far below depends on who you ask, and the
sources disagree enough that it's worth showing the spread rather than picking one:

| Source | Recommended size |
|---|---|
| [QASkills](https://qaskills.sh/blog/golden-dataset-llm-evaluation-guide) | 50–100 examples as minimum viable, *"to catch obvious failures"* |
| [Braintrust](https://www.braintrust.dev/articles/what-is-rag-evaluation) | at least 50–200 for meaningful evaluation |
| [Microsoft Data Science](https://medium.com/data-science-at-microsoft/the-path-to-a-golden-dataset-or-how-to-evaluate-your-rag-045e23d1f13f) | ~150 question/answer pairs, *"but certainly not less than 100"* |

Nobody puts the floor below 50. We are at 20.

**Standard metrics** ([DeepEval](https://deepeval.com/guides/guides-rag-evaluation),
[Patronus](https://www.patronus.ai/llm-testing/rag-evaluation-metrics)):

- **Retrieval:** precision@k, recall@k, MRR, nDCG
- **Generation:** faithfulness, relevance, citation coverage, hallucination rate

**What we already do right:** our correct answers come from the source document, not from a model.
That is the expensive half of a golden dataset, and it's done.

**What's missing:** getting past 50 questions, and separating the retrieval metric from the
generation one. Today we grade the final answer; we don't record whether the correct fragment even
reached the context.

**And something we did without knowing it was standard:** the 4 control questions measure
hallucination rate, which appears on every production metric list. Our result there was 0.

---

## 6. What healthcare demands beyond chunking

For what this is meant to sell, this matters as much as recall. Suresh Srinivas, of Collate, quoted
in [InformationWeek](https://www.informationweek.com/data-management/nobody-told-legal-about-your-rag-pipeline-why-that-s-a-problem):

> *"In a RAG database, data gets chunked — whether that's documents, database query results or
> structured data exports — and the metadata that establishes provenance, ownership and
> classification rarely travels with it."*

The article's own prescriptions are about governance rather than implementation: embedding *"audit
readiness checks into the AI development lifecycle"*, and preserving *"the source corpus, document
versions, retrieval results, timestamps, model prompts, and human review steps."*

That last list is the one that matters here, and **corpus versioning is the part we already
do** — the `retrieved` date travels with every fragment.

---

## Recommendation

**One, with its trade-off: chunk by the structure of the § and use parent-document retrieval.** Do
not raise `chunkSize`.

HIPAA arrives numbered (`§ 164.404`, `(c)`, `(1)`, `(A)`). It is the ideal case for structural
cutting.

**The trade-off:** cutting by structure means parsing the PDF's numbering, and Edtek warns exactly
about that:

> *"For PDFs of legal and scholarly content, the catch is that the structure has to actually be
> readable. PDFs vary wildly in how cleanly text extraction recovers the document's organisation."*

That's more work than changing a number, and it can fail if the extracted text comes out dirty.

**Before any of that, the one-minute experiment:** raise `topK` from 5 to 20 and re-run the seven
incomplete questions. Anthropic measured that top-20 beats top-5, and if the missing pieces are
sitting at ranks 6–20, they appear with no reindexing at all. **If it works, the problem is ranking
and not cutting** — and that changes which of the two fixes we need.

Edtek puts the same idea better than I can:

> *"The strategy you pick is less important than the strategy you calibrate."*

---

## Source audit — what survived verification and what didn't

Every quotation above was re-fetched from its page on 9 August 2026 and checked word by word.
**Six claims from the first version of this document did not survive**, and they are listed here
rather than quietly deleted.

### Removed: attributed to a source that doesn't say it

| Claim | Attributed to | What the page actually says |
|---|---|---|
| Golden dataset of **50–100 questions** | Qdrant | The page gives no starting size. *(The range is real — it's in QASkills, Braintrust and Microsoft, now cited above.)* |
| Hand-verified golden datasets are *"costly, slow and subjective"* | Qdrant | Not present |
| Late chunking gives **3.63% relative / 1.9% absolute** averaged over 3 models and 4 datasets | Jina AI | Only per-dataset figures. No average published |
| **8–15 points of recall@k** from section-based chunking on a contract corpus | Edtek | No benchmark figure anywhere on the page |
| *"Most RAG failures are retrieval failures, and most retrieval failures start at chunking"* | Unstructured | Not present |
| Chunk ID should be the section path; cross-references as metadata; audit log of retrieval decisions | InformationWeek | Not present. Only the provenance quotation is real |

### The subtlest one: a real quotation with its context removed

**Microsoft, on `reasoning_effort` for RAG.** This was cited as
*"RAG answering is a non-reasoning task"* — presented as a Microsoft finding.

The sentence exists. Here it is with what came before and after
([GPT-5: Will it RAG?](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/gpt-5-will-it-rag/4442676)):

> *"I have never seen it actually use any reasoning tokens when I set the effort to minimal, so
> **maybe** that means that a higher reasoning effort is really only needed for longer or more
> complex tasks, and RAG answering is a non-reasoning task. A higher reasoning effort would
> definitely affect the latency and likely also affect the answer quality. **I did not test that
> out**, since the 'minimal' effort setting already results in high quality answers."*

It is a `maybe`, followed by an explicit `I did not test that out`. Quoting the middle of that
turns one engineer's untested hypothesis into a measured conclusion from Microsoft.

**This is the failure mode worth remembering**, because it survives the obvious check: the words
are on the page, in that order. Searching for the sentence confirms it. Only reading the paragraph
around it shows the claim was never made.

**What the article does measure** is mean latency per model in its own RAG evaluation, and that is
usable:

| gpt-4.1-mini | 2.9 s |
| gpt-5-chat | 2.9 s |
| gpt-5-mini | **7.5 s** |
| gpt-5 | 9.6 s |
| o3-mini | 19.4 s |

*Method note: this page returned only its title through a plain fetch. It was recovered with a
different scraping tool. **A tool returning nothing is not evidence that nothing is there** — the
first version of this audit had already written the claim off as unverifiable.*

### What this changes about the conclusion

**Nothing.** The four sources carrying the argument — Zhou et al. on chunk size, Anthropic on
top-20, ZeroEntropy and Edtek on parent-document retrieval for legal text — **all verified
verbatim**.

What fell were the decorative claims. And that is the pattern worth keeping: **the six that failed
are the most quotable ones.** *"Most RAG failures are retrieval failures"* is a perfect line for a
report. It is also the one that doesn't exist. The ones that held up are the ones with ugly numbers
attached — 5.7%, $1.02, 64.20 → 66.10.

A round sentence with no number behind it is the one to check first.
