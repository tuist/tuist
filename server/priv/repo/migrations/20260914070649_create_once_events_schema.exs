defmodule Tuist.Repo.Migrations.CreateOnceEventsSchema do
  use Ecto.Migration

  # Every table this migration touches (once_runs, once_actions,
  # once_cache_events, once_system_samples, once_test_suite_runs,
  # once_test_case_runs) is introduced by this same unreleased change, so
  # the first time this runs there is no populated table to lock and no
  # concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file check_constraint_added
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  @moduledoc """
  The projected-state model for `once.events.v1` events, per RFC 0008.

  Two tables: `once_runs` stores one row per `once` command; `once_actions`
  stores each declared action that ran inside that command, keyed by
  `(run_id, target_execution_id, capability, action_index)` so retries and
  reingest are idempotent.
  """

  def change do
    create table(:once_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :run_id, :string, null: false, size: 128
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # Kind is derived server-side from the first target capability so the
      # dashboard can split Builds vs Tests without asking the client to pick.
      add :kind, :string, null: false, default: "build"

      # RunStarted metadata.
      add :once_version, :string, size: 64
      add :protocol_version, :string, size: 32
      add :host_class, :string, size: 128
      add :git_rev, :string, size: 128
      add :git_dirty, :boolean, default: false, null: false
      add :argv_normalized, :map, default: %{}
      add :argv_hash_key_id, :string, size: 128
      add :safe_literal_allowlist_version, :string, size: 64
      add :cwd_relative, :string, size: 512
      add :env_fingerprint, :string, size: 128
      add :root_graph_digest, :map, default: %{}
      add :effective_limits, :map, default: %{}

      # Rendered command line the CLI printed (kept for display; not the
      # projection key). Redacted client-side per RFC 0008 §Identity.
      add :command_display, :string, size: 512

      # Lifecycle.
      add :finalization, :string, null: false, default: "active"
      add :exit_status, :integer
      add :cancellation_reason, :string, size: 256
      add :wall_ms, :bigint

      # Roll-ups projected from once_actions as events land.
      add :total_actions, :integer, default: 0, null: false
      add :cached_actions, :integer, default: 0, null: false
      add :executed_actions, :integer, default: 0, null: false
      add :failed_actions, :integer, default: 0, null: false

      add :started_at, :timestamptz, null: false
      add :finalized_at, :timestamptz
      add :heartbeat_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:once_runs, [:project_id, :run_id], name: :once_runs_project_run_id_index)
    create index(:once_runs, [:project_id, :started_at])
    create index(:once_runs, [:project_id, :kind, :started_at])

    create constraint(:once_runs, :once_runs_finalization_bound,
             check:
               "finalization in ('active','finalizing','finalized','finalization_pending','lost')"
           )

    create constraint(:once_runs, :once_runs_kind_bound,
             check: "kind in ('build','test','generic')"
           )

    create table(:once_actions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, :string, null: false, size: 128
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :target_execution_id, :string, null: false, size: 512
      add :capability, :string, null: false, size: 64
      add :action_index, :integer, null: false, default: 0
      add :identifier, :string, size: 512

      add :result, :string, null: false
      add :was_cached, :boolean, null: false, default: false
      add :exit_code, :integer, null: false, default: 0
      add :duration_ms, :bigint, null: false, default: 0

      add :started_at, :timestamptz
      add :finished_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(
             :once_actions,
             [:once_run_id, :target_execution_id, :capability, :action_index],
             name: :once_actions_identity_index
           )

    create index(:once_actions, [:once_run_id, :finished_at])
    create index(:once_actions, [:project_id, :finished_at])

    create constraint(:once_actions, :once_actions_result_bound,
             check:
               "result in ('succeeded','failed','skipped','cancelled','timed_out','infrastructure_error')"
           )
  end
end
