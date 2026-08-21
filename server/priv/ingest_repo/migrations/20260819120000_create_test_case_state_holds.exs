defmodule Tuist.IngestRepo.Migrations.CreateTestCaseStateHolds do
  @moduledoc """
  Append-only ledger of test-case state hold operations: `claim`/`withdraw`
  rows per (test_case_id, alert_id) owner, resolved at read time with a
  per-owner `argMax` over `inserted_at`.

  `id` is part of the sort key on purpose: ReplacingMergeTree then collapses
  only identical re-inserted rows (idempotent re-inserts, e.g. backfill
  re-runs), while distinct operations are all preserved as the audit trail.

  No TTL, deliberately: a table-level TTL could eventually expire the latest
  row of a long-standing claim and silently release the hold. Row volume is
  small enough that history can be kept indefinitely; a TTL scoped to
  terminated history can be added later as its own careful change.
  """
  use Ecto.Migration

  def up do
    create table(:test_case_state_holds,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options: "ORDER BY (project_id, test_case_id, alert_id, id)"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :alert_id, :uuid, null: false
      add :test_case_id, :uuid, null: false
      add :op, :"LowCardinality(String)", null: false
      add :state, :"LowCardinality(String)", default: ""
      add :placed_at, :"DateTime64(6)", null: false
      add :actor_id, :"Nullable(Int64)"
      add :expiry_kind, :"LowCardinality(String)", default: "none"
      add :expires_at, :"Nullable(DateTime64(6))"
      add :expiry_runs, :"Nullable(Int32)"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end

  def down do
    drop table(:test_case_state_holds)
  end
end
