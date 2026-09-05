defmodule Tuist.Repo.Migrations.AddRunnerGithubActionsEnabledToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :runner_github_actions_enabled, :boolean, default: true, null: false
    end
  end
end
