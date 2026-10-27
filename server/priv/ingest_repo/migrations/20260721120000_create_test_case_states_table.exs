defmodule Tuist.IngestRepo.Migrations.CreateTestCaseStatesTable do
  use Ecto.Migration

  # `state` and `is_flaky` used to live on `test_cases`, a ReplacingMergeTree
  # whose rows are rewritten wholesale by test-report ingestion. Ingestion
  # snapshots the existing rows once per report and stamps `inserted_at` later,
  # per module, so a mute landing in that window was written with a *lower*
  # version than the ingestion row that carried the pre-mute value forward, and
  # the mute was silently reverted.
  #
  # This table is a projection of `test_case_events`, maintained by the
  # materialized view added alongside it. Nothing in the application writes it,
  # which is what makes the old race impossible: ingestion doesn't touch it, and
  # there is no second writer to disagree with the ledger.
  #
  # ## Why a plain MergeTree and nullable columns
  #
  # `state` and `is_flaky` change independently, and each event carries exactly
  # one of them. A row therefore records only the column its event affected and
  # leaves the other NULL, and reads resolve each column with its own
  # `argMaxIf(..., isNotNull(...))`.
  #
  # This is the crux of the fix. Collapsing to one row per test case (a
  # ReplacingMergeTree keyed on `(project_id, test_case_id)`) would replace rows
  # wholesale again, so a `marked_flaky` event would carry a stale `state`
  # alongside it and clobber a mute. Keeping the rows separate makes that
  # structurally impossible rather than a thing we have to order correctly.
  #
  # The table stays small: only state and flaky events land here, which is
  # ~129k rows against ~2.2M test cases, so the per-column aggregate is far
  # cheaper than deriving the same answer from `test_case_events` directly.
  def up do
    create table(:test_case_states,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, test_case_id, inserted_at)"
           ) do
      add :project_id, :Int64, null: false
      add :test_case_id, :uuid, null: false
      add :state, :"LowCardinality(Nullable(String))"
      add :is_flaky, :"Nullable(Bool)"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    # No secondary index on `test_case_id`. Every reader resolves the project
    # first and passes it down, so all of them ride the `(project_id,
    # test_case_id)` sort prefix and an index would be write-time cost for
    # nothing.
  end

  def down do
    drop table(:test_case_states)
  end
end
