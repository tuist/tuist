defmodule Tuist.Repo.Migrations.AddRunnerTrialToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :runner_trial_started_at, :timestamptz
      add :runner_trial_ended_at, :timestamptz
    end
  end
end
