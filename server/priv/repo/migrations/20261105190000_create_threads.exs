# All indexes belong to the new Threads tables created in this transaction, so there are no
# existing readers or writes to block while their indexes are built.
# excellent_migrations:safety-assured-for-this-file index_not_concurrently
defmodule Tuist.Repo.Migrations.CreateThreads do
  use Ecto.Migration

  def change do
    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :request_id, :uuid, null: false
      add :request_hash, :binary, null: false
      add :title, :text, null: false
      add :goal, :text, null: false
      add :provider, :text, null: false
      add :model, :text, null: false
      add :repository, :text
      add :base_branch, :text
      add :branch, :text
      add :base_sha, :text
      add :sandbox_id, references(:sandboxes, type: :binary_id, on_delete: :nilify_all)
      add :workspace_ready, :boolean, null: false, default: false
      add :ship_mode, :text, null: false, default: "branch"
      add :status, :text, null: false, default: "active"
      add :agent_status, :text, null: false, default: "queued"
      add :revision, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create unique_index(:threads, [:owner_id, :account_id, :request_id])
    # Tenant/owner equality followed by the stable inbox pagination pair.
    # excellent_migrations:safety-assured-for-next-line many_columns_index
    create index(:threads, [:owner_id, :account_id, :updated_at, :id])
    create index(:threads, [:account_id])
    create index(:threads, [:sandbox_id])

    create table(:thread_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :request_id, :uuid
      add :position, :bigint, null: false
      add :kind, :text, null: false
      add :body, :text
      add :tool_name, :text
      add :tool_state, :text
      add :suggestions, {:array, :text}, null: false, default: []
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_messages, [:thread_id, :position])
    create unique_index(:thread_messages, [:thread_id, :request_id])

    create table(:thread_ship_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :request_id, :uuid, null: false
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :repository, :text, null: false
      add :sandbox_id, references(:sandboxes, type: :binary_id, on_delete: :nilify_all)
      add :head_sha, :text, null: false
      add :base_sha, :text
      add :diff, :text, null: false
      add :target_branch, :text, null: false
      add :mode, :text, null: false
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :approved_at, :timestamptz
      add :status, :text, null: false, default: "pending"
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_ship_approvals, [:thread_id, :request_id])
    create index(:thread_ship_approvals, [:account_id])
    create index(:thread_ship_approvals, [:sandbox_id])
    create index(:thread_ship_approvals, [:approved_by_id])

    create table(:thread_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :message_id, references(:thread_messages, type: :binary_id, on_delete: :nilify_all)

      add :approval_id,
          references(:thread_ship_approvals, type: :binary_id, on_delete: :nilify_all)

      add :kind, :text, null: false, default: "inference"
      add :status, :text, null: false, default: "queued"
      add :attempt, :integer, null: false, default: 0
      add :session_id, :uuid
      add :heartbeat_at, :timestamptz
      add :checkpoint, :binary
      timestamps(type: :timestamptz)
    end

    create index(:thread_runs, [:thread_id, :status])

    create unique_index(:thread_runs, [:thread_id],
             where: "status IN ('queued', 'running')",
             name: :thread_runs_one_active
           )

    create unique_index(:thread_runs, [:session_id])
    create index(:thread_runs, [:heartbeat_at, :id], where: "status IN ('queued', 'running')")
    create index(:thread_runs, [:message_id])
    create index(:thread_runs, [:approval_id])

    create table(:thread_tool_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:thread_runs, type: :binary_id, on_delete: :delete_all), null: false
      add :message_id, references(:thread_messages, type: :binary_id, on_delete: :nilify_all)
      add :fingerprint, :binary, null: false
      add :name, :text, null: false
      add :status, :text, null: false, default: "executing"
      add :checkpointed, :boolean, null: false, default: false
      add :result, :binary
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_tool_calls, [:run_id, :fingerprint])
    create index(:thread_tool_calls, [:message_id])

    create table(:thread_inboxes, primary_key: false) do
      add :owner_id, references(:users, on_delete: :delete_all), primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), primary_key: true
      add :revision, :bigint, null: false, default: 0
    end

    create index(:thread_inboxes, [:account_id])
  end
end
