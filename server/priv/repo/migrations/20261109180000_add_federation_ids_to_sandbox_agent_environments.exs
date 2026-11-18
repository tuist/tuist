defmodule Tuist.Repo.Migrations.AddFederationIdsToSandboxAgentEnvironments do
  use Ecto.Migration

  # The Anthropic Workload Identity Federation ids an agent environment
  # exchanges Tuist-signed tokens with instead of a stored API key. None of
  # them is a secret.
  def change do
    alter table(:sandbox_agent_environments) do
      add :anthropic_organization_id, :string
      add :anthropic_workspace_id, :string
      add :anthropic_service_account_id, :string
      add :anthropic_federation_rule_id, :string
    end
  end
end
