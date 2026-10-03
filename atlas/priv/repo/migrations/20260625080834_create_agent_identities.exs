defmodule Atlas.Repo.Migrations.CreateAgentIdentities do
  use Ecto.Migration

  def change do
    create table(:agent_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :key, :string, null: false
      add :display_name, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 0
      add :bindings, :map, null: false, default: %{}

      add :persona, :string, null: false, default: "default"
      add :tool_groups, {:array, :string}, null: false, default: []
      add :tool_groups_by_agent, :map, null: false, default: %{}
      add :service_user_email, :string
      add :memory_scope, :string, null: false, default: "global"
      add :requester_rules, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:agent_identities, [:key])
    create index(:agent_identities, [:enabled])
    create index(:agent_identities, [:bindings], using: "gin")
  end
end
