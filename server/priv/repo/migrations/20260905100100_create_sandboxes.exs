defmodule Tuist.Repo.Migrations.CreateSandboxes do
  use Ecto.Migration

  # One row per Firecracker sandbox VM. `state` is one of
  # creating|running|paused|error|deleted. `node_name` is the sandboxd node
  # holding the jail directory. `residency_work_id` is the Anthropic work
  # item whose worker currently runs inside the VM; `residency_epoch` is
  # bumped every time a residency ends so a scheduled pause can tell
  # whether a newer residency started after it was enqueued.
  def change do
    create table(:sandboxes, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :agent_environment_id, references(:sandbox_agent_environments, on_delete: :nilify_all)
      add :anthropic_session_id, :string
      add :template, :string
      add :template_tag, :string
      add :vcpus, :integer
      add :memory_mb, :integer
      add :workspace_gb, :integer
      add :state, :string, null: false, default: "creating"
      add :node_name, :string
      add :hostname, :string
      add :residency_work_id, :string
      add :residency_epoch, :integer, null: false, default: 0
      add :last_active_at, :timestamptz
      add :paused_at, :timestamptz
      add :error_message, :text

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:sandboxes, [:agent_environment_id, :anthropic_session_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandboxes, [:account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandboxes, [:node_name])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:sandboxes, [:state])
  end
end
