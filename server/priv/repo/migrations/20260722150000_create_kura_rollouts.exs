defmodule Tuist.Repo.Migrations.CreateKuraRollouts do
  @moduledoc """
  Durable control-plane state for health-gated progressive rollouts of the
  Kura runtime image (spec #79).

  `kura_rollouts` is one rollout of one image tag in this environment; at
  most one rollout is non-terminal at a time (partial unique index).
  `kura_rollout_wave_assignments` freezes the account -> wave grouping at
  rollout creation. `kura_rollout_servers` tracks per-server rollout scope:
  the pre-upgrade health baseline, soak eligibility, the deployment minted
  for the current attempt, and convergence. `kura_rollout_events` is the
  operator/audit trail.
  """
  use Ecto.Migration

  def change do
    create table(:kura_rollouts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :image_tag, :string, null: false
      add :baseline_image_tag, :string
      # 0 running, 1 paused, 2 completed, 3 aborted, 4 superseded
      add :status, :integer, null: false, default: 0
      # 0 progressive, 1 expedited
      add :mode, :integer, null: false, default: 0
      add :current_wave, :integer, null: false, default: 0
      add :wave_started_at, :timestamptz
      add :wave_healthy_since, :timestamptz
      add :paused_at, :timestamptz
      add :pause_reason, :text
      add :completed_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_rollouts, :kura_rollouts_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_rollouts, :kura_rollouts_mode_valid, check: "mode IN (0, 1)")

    # At most one non-terminal (running/paused) rollout per environment: a
    # new tag supersedes the active rollout before its own row is created.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_rollouts, ["(1)"],
             name: :kura_rollouts_single_active_index,
             where: "status IN (0, 1)"
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollouts, [:image_tag, :inserted_at])

    create table(:kura_rollout_wave_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :kura_rollout_id,
          references(:kura_rollouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :wave, :integer, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_rollout_wave_assignments, [:kura_rollout_id, :account_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollout_wave_assignments, [:kura_rollout_id, :wave])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollout_wave_assignments, [:account_id])

    create table(:kura_rollout_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :kura_rollout_id,
          references(:kura_rollouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :kura_server_id,
          references(:kura_servers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :wave, :integer, null: false
      add :attempt, :integer, null: false, default: 0
      add :soak_eligible, :boolean, null: false, default: true
      add :baseline_outbox_messages, :bigint
      add :baseline_fd_timeout_count, :bigint
      add :baseline_peer_connection_failures, :bigint
      add :baseline_captured_at, :timestamptz

      add :deployment_id,
          references(:kura_deployments, type: :binary_id, on_delete: :nilify_all)

      add :converged_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_rollout_servers, [:kura_rollout_id, :kura_server_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollout_servers, [:kura_rollout_id, :wave])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollout_servers, [:kura_server_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollout_servers, [:deployment_id])

    create table(:kura_rollout_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :kura_rollout_id,
          references(:kura_rollouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :action, :string, null: false
      add :actor, :string, null: false
      add :reason, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_rollout_events, [:kura_rollout_id, :inserted_at])

    alter table(:kura_deployments) do
      # Which rollout minted this deployment; null for pre-rollout history,
      # server creation installs, moves, and operator retries.
      add :kura_rollout_id, references(:kura_rollouts, type: :binary_id, on_delete: :nilify_all)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_deployments, [:kura_rollout_id])
  end
end
