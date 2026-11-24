defmodule LuftServer.Repo.Migrations.CreateThreads do
  use Ecto.Migration

  def change do
    create table(:thread_runners, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :bigint, null: false
      add :name, :text, null: false
      add :platform, :text, null: false
      add :token_hash, :binary, null: false
      add :capabilities, :map, null: false, default: %{}
      add :last_seen_at, :timestamptz
      add :revoked_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_runners, [:token_hash])
    create index(:thread_runners, [:user_id])

    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Upstream identities and sandboxes must never become local foreign keys.
      add :account_id, :bigint, null: false
      add :account_handle, :text
      add :owner_id, :bigint, null: false
      add :owner_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
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
      add :sandbox_id, :uuid
      add :runner_id, references(:thread_runners, type: :binary_id, on_delete: :nilify_all)
      add :workspace_ready, :boolean, null: false, default: false
      add :ship_mode, :text, null: false, default: "branch"
      add :status, :text, null: false, default: "active"
      add :snoozed_until, :timestamptz
      add :snoozed_until_needed, :boolean, null: false, default: false
      add :agent_status, :text, null: false, default: "queued"
      add :revision, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create unique_index(:threads, [:owner_id, :account_id, :request_id])
    create index(:threads, [:owner_id, :account_id, :updated_at, :id])
    create index(:threads, [:account_id])
    create index(:threads, [:sandbox_id])
    create index(:threads, [:runner_id])
    create index(:threads, [:owner_session_id])

    create table(:thread_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :request_id, :uuid
      add :position, :bigint, null: false
      add :kind, :text, null: false
      add :author_id, :bigint
      add :author_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      add :body, :text
      add :attachments, {:array, :map}, null: false, default: []
      add :tool_name, :text
      add :tool_state, :text
      add :suggestions, {:array, :text}, null: false, default: []
      add :suggestion_icons, :map
      add :card_size, :text
      add :card_source, :text
      add :decision, :map
      add :progress, :map
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_messages, [:thread_id, :position])
    create unique_index(:thread_messages, [:thread_id, :request_id])
    create index(:thread_messages, [:author_id])
    create index(:thread_messages, [:author_session_id])

    create table(:thread_participants, primary_key: false) do
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, :bigint, primary_key: true
      add :added_by_id, :bigint
      timestamps(type: :timestamptz)
    end

    create index(:thread_participants, [:user_id])
    create index(:thread_participants, [:added_by_id])

    create table(:thread_ship_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :request_id, :uuid, null: false
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :account_id, :bigint, null: false
      add :repository, :text, null: false
      add :sandbox_id, :uuid
      add :head_sha, :text, null: false
      add :base_sha, :text
      add :diff, :text, null: false
      add :target_branch, :text, null: false
      add :mode, :text, null: false
      add :approved_by_id, :bigint
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
      add :waited_seconds, :bigint, null: false, default: 0
      add :checkpoint, :binary
      timestamps(type: :timestamptz)
    end

    create index(:thread_runs, [:thread_id, :status])

    create unique_index(:thread_runs, [:thread_id],
             where: "status IN ('queued', 'running', 'waiting')",
             name: :thread_runs_one_unfinished
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
      add :invocation_id, :string
      add :status, :text, null: false, default: "executing"
      add :checkpointed, :boolean, null: false, default: false
      add :result, :binary
      timestamps(type: :timestamptz)
    end

    create unique_index(:thread_tool_calls, [:run_id, :fingerprint])
    create index(:thread_tool_calls, [:message_id])

    create table(:thread_runner_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :runner_id, references(:thread_runners, type: :binary_id, on_delete: :delete_all),
        null: false

      add :op, :text, null: false
      add :payload, :map, null: false
      add :status, :text, null: false, default: "pending"
      add :response, :map
      add :claimed_at, :timestamptz
      add :expires_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create index(:thread_runner_requests, [:runner_id, :status, :inserted_at])
    create index(:thread_runner_requests, [:expires_at])

    # Inbox revisions have no Ecto schema in the source context either.
    create table(:thread_inboxes, primary_key: false) do
      add :owner_id, :bigint, primary_key: true
      add :account_id, :bigint, primary_key: true
      add :revision, :bigint, null: false, default: 0
    end

    create index(:thread_inboxes, [:account_id])
  end
end
