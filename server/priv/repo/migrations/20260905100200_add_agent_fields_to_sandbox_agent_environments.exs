defmodule Tuist.Repo.Migrations.AddAgentFieldsToSandboxAgentEnvironments do
  use Ecto.Migration

  # `anthropic_api_key` is Cloak-encrypted via `Tuist.Vault.Binary` and lets
  # the server create Managed Agents agents and sessions on the account's
  # behalf. `anthropic_agent_id` caches the agent Tuist created for the
  # environment's `agent_model` and `agent_system_prompt`.
  def change do
    alter table(:sandbox_agent_environments) do
      add :anthropic_api_key, :binary
      add :anthropic_agent_id, :string
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :agent_model, :string, null: false, default: "claude-sonnet-5"
      add :agent_system_prompt, :text
    end
  end
end
