defmodule Tuist.IngestRepo.Migrations.CreateModuleCacheTransferDurations do
  @moduledoc """
  Stores the per-command wall-clock time spent transferring module (binary) cache
  artifacts, surfaced as the run's overall module cache fetch time.

  It lives in a dedicated table rather than a `command_events` column so it stays
  symmetric with `module_cache_outputs` (project + inserted_at scoped) and avoids
  re-populating the `command_events` materialized views for a single scalar. The
  per-operation durations in `module_cache_outputs` cannot be summed into this
  because transfers run concurrently, so the CLI reports the measured span.
  """
  use Ecto.Migration

  def change do
    create table(:module_cache_transfer_durations,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, inserted_at)"
           ) do
      add :command_event_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :duration_ms, :UInt32, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
