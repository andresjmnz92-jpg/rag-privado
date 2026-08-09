# Getting real documents into a RAG: which converter, and in what format

*Research, 9 August 2026 · Written to choose a tool before building anything, not to justify one
already chosen · Every number below is attributed; the two unverified assumptions are marked as
such at the end.*

## Short version

A RAG is only as good as what it is fed, and real companies do not hand you clean XML. They hand
you PDFs, Word files, spreadsheets and scans. **The conversion step is where most of the quality is
won or lost**, and it is the step tutorials skip because their example PDF is already clean.

Three open-source converters are worth knowing. The choice is not about which is "best" — it is
about **what kind of documents the client has**.

## The three converters

| | Docling | Marker | MinerU |
|---|---|---|---|
| Maintainer | IBM Research | VikParuchuri | OpenDataLab (Shanghai AI Lab) |
| Licence | **MIT** | GPL-3.0, **model weights need a commercial licence above $2M revenue** | Apache-2.0 with conditions |
| Input | PDF, DOCX, PPTX, XLSX, HTML, EPUB, images, EML/MSG, audio | PDF, images | PDF, images |
| Output | Markdown, HTML, DocTags, lossless JSON | Markdown + LaTeX | Markdown + JSON |
| Strongest at | **Tables** (TableFormer) and Office files | Throughput on clean PDFs | **Formulas** (UniMERNet) |

Input formats, output formats and the MIT licence read from the
[Docling repository](https://github.com/docling-project/docling) on 9 Aug 2026. The licence
condition on Marker's weights and MinerU's formula advantage come from a
[vendor comparison](https://www.spheron.network/blog/self-host-document-intelligence-docling-marker-mineru-rag-guide/)
— **a secondary source, not verified against Marker's own licence file.**

### Why Docling for this project

1. **MIT.** No revenue threshold, no clause that turns into a bill the day something gets sold.
2. **It reads what companies actually have.** DOCX, XLSX and PPTX natively — the other two take
   PDFs and images only. A clinic's price list is a spreadsheet, not a PDF.
3. **It runs on CPU.** Its own paper ([arXiv 2501.17887](https://arxiv.org/html/2501.17887v1))
   measures **0.79 s per page median on x86 CPU**, and states that **disabling OCR saves 60% of
   runtime on CPU**. The server behind this project has 4 vCPU and no GPU, so this is not a
   preference — it is the constraint that eliminates the alternatives.

### When to reach for MinerU instead

**A corpus with heavy mathematics or chemistry**: technical datasheets, lab protocols, engineering
specs, scientific papers. MinerU's UniMERNet formula recognition is described as clearly ahead of
both others there, and Docling's formula handling as limited. Also cited as the better option for
Chinese, Japanese and Korean.

Worth keeping even though this project has no formulas: **the choice of converter is a per-client
decision, not a permanent one.** A pharmaceutical or engineering client changes the answer, and the
cost of finding that out mid-project is a full reindex.

### When Marker fits

Bulk ingestion of large, reasonably clean PDF corpora where speed matters more than table fidelity
and the output goes straight to an embedding model. **Check the weight licence first if there is any
chance of commercial use.**

## The format question: Markdown is the default, and for tables it is the wrong one

Almost every RAG tutorial converts everything to Markdown. For prose that is fine. For tables the
measurements disagree.

*Table Meets LLM* ([arXiv 2305.13062](https://arxiv.org/html/2305.13062v4)) benchmarks the same
tables serialised six ways. With GPT-4:

| Task | Markdown | HTML |
|---|---|---|
| Column retrieval | 60.12% | **69.32%** |
| Cell lookup | 71.93% | **73.34%** |
| Size detection | 82.12% | **83.43%** |
| HybridQA (table + text) | 45.88% | **47.29%** |
| Feverous | 71.88% | **75.20%** |
| TabFact | 68.40% | **71.33%** |

*Large Language Model for Table Processing: A Survey*
([arXiv 2402.05121](https://arxiv.org/html/2402.05121v3)) reaches the same conclusion across the
literature: *"HTML and NL with separators (markdown or CSV) are the two most effective options,
which can be assumed that the training corpora include substantial code and web tables."*

The stated reason matters more than the numbers: models saw a great deal of HTML during training.
That is an argument that will hold for the next model too, unlike a tuning result.

**Docling exports both**, so this is a choice, not a limitation.

## Two assumptions, written down before they can be mistaken for findings

1. **That HTML tables should also be embedded that way.** The benchmarks above measure a model
   *reading* a table already in its context — they say nothing about embedding quality. Markup tags
   are tokens too, and they may dilute the vector. The plausible design is **index in Markdown,
   deliver in HTML**, and it is untested.
2. **That Marker's weight licence carries a $2M revenue threshold.** Read in a vendor comparison,
   not in Marker's own licence file. If Marker ever becomes the candidate, read the licence first.

Both are cheap to settle, and this project has already paid once for the difference between an
assumption and a fact.
