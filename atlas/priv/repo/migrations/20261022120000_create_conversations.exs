defmodule Atlas.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    alter table(:inference_model_bindings) do
      add :atlas_conversations, :boolean, null: false, default: false
    end

    create unique_index(:inference_model_bindings, [:atlas_conversations],
             where: "atlas_conversations",
             name: :inference_model_bindings_single_atlas_conversations_index
           )

    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "active"
      add :summary, :text, null: false, default: ""
      add :origin, :string, null: false, default: "manual"
      add :source_type, :string
      add :source_id, :string
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :required_scopes, {:array, :string}, null: false, default: []
      add :last_seq, :bigint, null: false, default: 0
      timestamps(type: :timestamptz)
    end

    create unique_index(:conversations, [:owner_id],
             where: "kind = 'private'",
             name: :conversations_single_private_thread_index
           )

    create unique_index(:conversations, [:source_type, :source_id],
             where: "origin = 'signal' AND status = 'active'",
             name: :conversations_active_signal_source_index
           )

    create index(:conversations, [:updated_at])

    create constraint(:conversations, :conversations_kind, check: "kind IN ('private', 'shared')")

    create constraint(:conversations, :conversations_status,
             check: "status IN ('active', 'archived')"
           )

    create constraint(:conversations, :conversations_origin,
             check: "origin IN ('manual', 'signal')"
           )

    create table(:conversation_participants, primary_key: false) do
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :role, :string, null: false, default: "member"
      timestamps(type: :timestamptz, updated_at: false)
    end

    create index(:conversation_participants, [:user_id])

    create table(:conversation_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :initiator_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :acting_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :model_binding_id,
          references(:inference_model_bindings, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "queued"
      add :trigger_seq, :bigint, null: false
      add :resume_count, :integer, null: false, default: 0
      add :session_id, :string
      add :checkpoint, :binary
      add :checkpoint_turn, :integer
      add :error_category, :string
      add :cancel_requested_at, :timestamptz
      add :started_at, :timestamptz
      add :heartbeat_at, :timestamptz
      add :finished_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:conversation_runs, [:conversation_id],
             where: "status IN ('queued', 'running')",
             name: :conversation_runs_single_active_index
           )

    create index(:conversation_runs, [:status, :heartbeat_at])

    create constraint(:conversation_runs, :conversation_runs_status,
             check:
               "status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled', 'interrupted')"
           )

    create table(:conversation_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :run_id, references(:conversation_runs, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :body, :text, null: false, default: ""
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :author_name, :string, null: false, default: ""
      add :client_id, :uuid
      add :address_agent, :boolean, null: false, default: false
      add :tool_name, :string
      add :tool_status, :string
      add :tool_input, :text, null: false, default: ""
      add :tool_output, :text, null: false, default: ""
      add :tool_call_key, :string
      add :tool_result, :binary
      add :position, :bigint, null: false
      add :seq, :bigint, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:conversation_messages, [:conversation_id, :position])
    create index(:conversation_messages, [:conversation_id, :seq])
    create index(:conversation_messages, [:run_id, :tool_call_key])

    create unique_index(:conversation_messages, [:conversation_id, :author_id, :client_id],
             where: "client_id IS NOT NULL",
             name: :conversation_messages_client_id_index
           )

    create constraint(:conversation_messages, :conversation_messages_kind,
             check: "kind IN ('human', 'agent', 'tool', 'system')"
           )

    create table(:conversation_viewers, primary_key: false) do
      add :connection_id, :uuid, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :typing_until, :timestamptz

      add :expires_at, :timestamptz,
        null: false,
        default: fragment("clock_timestamp() + interval '20 seconds'")
    end

    create index(:conversation_viewers, [:conversation_id])
    create index(:conversation_viewers, [:expires_at])
  end
end
