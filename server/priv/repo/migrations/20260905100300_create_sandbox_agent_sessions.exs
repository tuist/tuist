defmodule Tuist.Repo.Migrations.CreateSandboxAgentSessions do
  use Ecto.Migration

  # One row per Managed Agents session Tuist started on an account's
  # connected environment. Anthropic owns the conversation; the row keeps
  # the Anthropic ids, what was asked, the budget and the last status the
  # server saw. `sandbox_id` is bound by the router once the session's
  # first work item creates its VM.
  def change do
    create table(:sandbox_agent_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :agent_environment_id, references(:sandbox_agent_environments, on_delete: :delete_all),
        null: false

      add :anthropic_session_id, :string, null: false
      add :anthropic_agent_id, :string, null: false
      add :sandbox_id, references(:sandboxes, type: :uuid, on_delete: :nilify_all)
      add :title, :string
      add :prompt, :text, null: false
      add :repository_url, :string
      add :repository_ref, :string
      add :model, :string
      add :budget_cents, :integer
      add :last_status, :string
      add :last_stop_reason, :string
      add :created_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:sandbox_agent_sessions, [:anthropic_session_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandbox_agent_sessions, [:account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandbox_agent_sessions, [:agent_environment_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandbox_agent_sessions, [:sandbox_id])
  end
end
