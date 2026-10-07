defmodule Tuist.Repo.Migrations.ExtendOnceEventsWithCache do
  use Ecto.Migration

  # Every table this migration touches (once_runs, once_actions,
  # once_cache_events, once_system_samples, once_test_suite_runs,
  # once_test_case_runs) is introduced by this same unreleased change, so
  # the first time this runs there is no populated table to lock and no
  # concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file check_constraint_added
  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  @moduledoc """
  Adds cache byte roll-ups to `once_runs` and a `once_cache_events` table
  so the Once run dashboard can render the same Cache tab shape as
  Bazel: five summary tiles (hits, misses, hit rate, content
  downloaded, content uploaded), a Cacheable Actions list with cache
  key / latency / observed columns, and a Content Objects list with
  content-address digests and byte sizes.

  See RFC 0008 §Cache events (`CacheUpload`, `CacheDownload`,
  `CacheStoreReused`). The projector accepts those wire events into
  this table.
  """

  def change do
    alter table(:once_runs) do
      add :cache_bytes_downloaded, :bigint, default: 0, null: false
      add :cache_bytes_uploaded, :bigint, default: 0, null: false
      add :cache_bytes_saved, :bigint, default: 0, null: false
      add :cache_action_read_count, :integer, default: 0, null: false
      add :cache_action_read_ms_total, :bigint, default: 0, null: false
      add :cache_action_write_count, :integer, default: 0, null: false
      add :cache_action_write_ms_total, :bigint, default: 0, null: false
    end

    create table(:once_cache_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, :string, null: false, size: 128
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # Which cache event this row projected from. Matches the RFC 0008
      # oneof names 1:1: `upload`, `download`, `reused`.
      add :kind, :string, null: false

      # Optional target-execution context. Empty for content-only
      # events that aren't associated with a target.
      add :target_execution_id, :string, size: 512

      # Deterministic per-lookup id from the Once client. Lets a
      # download and its later upload cluster on the same key.
      add :cache_decision_id, :string, size: 128

      # Storage tier the client hit (e.g. `remote`, `local`,
      # `memory`). Stored verbatim; the projector does not fold tiers.
      add :tier, :string, size: 64

      # Emitter-supplied category: `action_cache`, `content_cache`,
      # `metadata`, etc. Used to split the cacheable-actions view from
      # the content-objects view.
      add :category, :string, size: 64

      # Content-address digest of the object (BLAKE3 in the RFC).
      # Empty for events that only carry byte counts (rare).
      add :content_hash, :string, size: 128
      add :content_size_bytes, :bigint, default: 0, null: false

      # Wire bytes moved for this event. Zero for `reused` where the
      # cost was saved. `bytes_saved` from `CacheStoreReused` lives
      # here too, tagged by `kind = "reused"`.
      add :bytes_transferred, :bigint, default: 0, null: false
      add :duration_ms, :bigint, default: 0, null: false

      # Cache outcome for the client's own view of the lookup:
      # `hit`, `miss`, `stored`, `reused`. Feeds the row's chip on
      # the Cacheable Actions table.
      add :outcome, :string, size: 32

      add :observed_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create index(:once_cache_events, [:once_run_id, :observed_at])
    create index(:once_cache_events, [:project_id, :observed_at])
    create index(:once_cache_events, [:once_run_id, :kind])
    create index(:once_cache_events, [:once_run_id, :target_execution_id])

    create constraint(:once_cache_events, :once_cache_events_kind_bound,
             check: "kind in ('upload','download','reused')"
           )
  end
end
