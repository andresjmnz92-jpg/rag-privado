-- Hybrid retrieval: vector search and full-text search fused with Reciprocal
-- Rank Fusion, in one statement.
--
-- Shape taken from pgvector's own example:
-- https://github.com/pgvector/pgvector-python/blob/master/examples/hybrid_search/rrf.py
--
-- Parameters, in this order:
--   $1  the question already turned into a vector by bge-m3 (same model used at index time)
--   $2  the question as plain text
--
-- Every decision below was measured on this corpus on 2026-08-09. The numbers
-- quoted in the comments are from that session, not from a blog post.
--
-- ---------------------------------------------------------------------------
-- VERDICT, 2026-08-09: on this corpus this query is WORSE than plain vector
-- search. Do not wire it into the agent.
--
--   Recall@10   plain vector 16/16   hybrid 13/16
--   MRR         plain vector 0.865   hybrid 0.435
--
-- Measured with evaluacion/medir-recuperacion.py over the 16 golden questions
-- that have a known section. It made 8 questions worse, 1 better, and lost 3
-- outright.
--
-- The reason was written below as a known limit before the numbers existed: the
-- documents are English, the questions are Spanish, so the lexical half cannot
-- contribute — and it holds 70% of the weight. Hybrid search is a good default
-- that this corpus punishes.
--
-- The file stays because the query is correct and the finding is the point: a
-- recommended technique, measured, that turned out to hurt. Ordinary vector
-- search with a multilingual embedding model was already at the ceiling.
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- Run once. Without it the lexical half does a sequential scan.
-- ---------------------------------------------------------------------------
-- CREATE INDEX documentos_v2_fts ON documentos_v2
--     USING GIN (to_tsvector('english', text));


WITH entrada AS (
    SELECT
        $1::vector AS v,

        -- The documents are English and the questions are Spanish, so the two
        -- halves cannot be queried the same way.
        --
        -- `plainto_tsquery` joins every word with AND. A real question —
        -- "cual es el plazo para notificar segun 164.404" — then demands that
        -- "cual", "plazo" and "notificar" all appear in an English document.
        -- Measured: 0 rows. The Spanish words do not merely fail to help, they
        -- kill the identifier along with them.
        --
        -- Joining with OR instead makes the Spanish words simply mute: they
        -- match nothing and cost nothing, and the identifier does the work.
        -- Measured: the same 4 rows as searching the bare "164.404", with no
        -- extra noise. That is why there is no identifier-extraction step here.
        --
        -- to_tsvector runs first because it handles the punctuation, the
        -- opening "¿" and the casing before anything is joined.
        --
        -- NULLIF guards the edge case: a question that leaves no lexemes would
        -- produce ''::tsquery and raise. NULL makes `@@` match nothing, so the
        -- query degrades to vector-only instead of failing.
        NULLIF(
            array_to_string(
                tsvector_to_array(to_tsvector('english', $2)),
                ' | '
            ), ''
        )::tsquery AS q
),

-- 20 candidates from each side, not 10. Over-fetching gives the fusion more
-- signal; the pgvector example uses the same figure.
semantica AS (
    SELECT id, RANK() OVER (ORDER BY embedding <=> (SELECT v FROM entrada)) AS puesto
    FROM documentos_v2
    ORDER BY embedding <=> (SELECT v FROM entrada)
    LIMIT 20
),

lexica AS (
    SELECT id, RANK() OVER (
               ORDER BY ts_rank_cd(to_tsvector('english', text), (SELECT q FROM entrada)) DESC
           ) AS puesto
    FROM documentos_v2
    WHERE to_tsvector('english', text) @@ (SELECT q FROM entrada)
    ORDER BY ts_rank_cd(to_tsvector('english', text), (SELECT q FROM entrada)) DESC
    LIMIT 20
)

-- Reciprocal Rank Fusion: 1 / (k + rank), summed across both lists.
--
-- Ranks are used instead of scores because cosine distance and ts_rank_cd are
-- not on comparable scales — normalising them would mean inventing a mapping.
-- RRF only cares about position, so no mapping is needed.
--
-- k = 60 comes from Cormack et al. (2009) and is the value in pgvector's
-- example. It is a starting point to be measured, not a constant of nature.
--
-- The 0.7 / 0.3 split leans lexical, following ParadeDB: their 70/30 "works
-- well for technical documentation where users often search for specific
-- terms, function names, or error messages." A corpus of § 164.404 and
-- (c)(1)(A) is exactly that.
--
-- What the fusion buys, measured on ONE question: searching "164.404" on the
-- lexical side alone ranked the section that DEFINES it **last**, behind three
-- sections that merely cross-reference it — ts_rank_cd rewards repetition and
-- knows nothing about the corpus. After fusion it ranked **first**, because it
-- is the only fragment both searches found.
--
-- That paragraph was written after one question and it reads like a result. It
-- is not. Across all 16 the fusion loses to plain vector search — see the
-- verdict at the top. One good example is an anecdote; the anecdote is what
-- made this look like it worked.
SELECT
    d.text,
    d.metadata->>'seccion'  AS seccion,
    d.metadata->>'citation' AS citation,
    COALESCE(0.3 / (60 + s.puesto), 0.0) +
    COALESCE(0.7 / (60 + l.puesto), 0.0) AS puntaje
FROM semantica s
FULL OUTER JOIN lexica l ON s.id = l.id
JOIN documentos_v2 d ON d.id = COALESCE(s.id, l.id)
ORDER BY puntaje DESC
LIMIT 10;


-- Known limits, written before the evaluation rather than after:
--
--   * This is `ts_rank_cd`, not BM25. BM25 needs ParadeDB's pg_search
--     extension, which this image does not carry. ts_rank_cd scores each
--     document in isolation and has no corpus-wide term statistics, so it
--     cannot tell a rare term from a common one.
--
--   * The OR query was validated on one question. Spanish words that happen to
--     be English words too ("individual", "total") could still drag in noise.
--
--   * Two fragments of the same section can both surface, one from each side,
--     so the writer may receive overlapping context.
--
--   * The embedding column is declared `vector` with no dimension, so it cannot
--     take a plain HNSW index — only an expression index with a cast. At 653
--     rows the sequential scan is not the bottleneck; at scale it would be.
