defmodule Tuist.Repo.Migrations.ChangeRunnerJobsErrorMessageToText do
  use Ecto.Migration

  def change do
    alter table(:runner_jobs) do
      modify :error_message, :text
    end
  end
end
