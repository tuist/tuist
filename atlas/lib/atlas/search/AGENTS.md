# Search projections

`Atlas.Search` owns PostgreSQL search records and their rebuildable vector projection.
Domain records remain authoritative. Existing callers retain their normal indexing
behavior; Automation calls use `Search.with_deferred_vectors/1` so network effects
cannot escape a rolled-back domain action.

- The deferred context is process-local and restores the previous value on success,
  failure and nested calls. Do not replace it with application environment state.
- Deferred upserts/deletions enqueue `VectorWorker` through the same database
  transaction. Jobs carry operation and record IDs only, not source bodies, embeddings,
  credentials or actor tokens.
- Upserts reload current committed search records. A missing/deleted record is a
  harmless no-op. Deletion addresses the original search-record vector ID.
- Vector indexing remains best-effort and rebuildable, not an atomic external effect
  or an exactly-once delivery guarantee. Do not claim immediate semantic-search
  visibility when a domain action commits.
- Keep failure logs fixed and payload-free. `search_record_id` is allowed operational
  metadata; raw embedding/provider error terms may contain private source text.
- Domain workflow tests must cover output-contract rollback removing both the domain
  row and its PostgreSQL search record, and retry producing only one committed effect.

- Moodboard resources and comments use the same deferred transaction boundary.
  `moodboard_resource` indexes contributor notes, original text and bounded fetched
  source text and independent hostname terms; `moodboard_comment` indexes each discussion contribution separately
  so embedding input truncation cannot crowd out comments behind an article.
  Both resolve to the authenticated resource detail page. Resource deletion removes
  both kinds of projection; title changes refresh related comment titles. Backfill
  rebuilds both from domain rows. See [`../moodboard/AGENTS.md`](../moodboard/AGENTS.md).

The Automation transaction and contract boundaries are documented in
[`../automations/AGENTS.md`](../automations/AGENTS.md).
