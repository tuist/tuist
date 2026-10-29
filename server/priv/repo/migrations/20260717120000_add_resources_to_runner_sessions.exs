defmodule Tuist.Repo.Migrations.AddResourcesToRunnerSessions do
  use Ecto.Migration

  def change do
    alter table(:runner_sessions) do
      add :platform, :string
      add :vcpus, :integer
      add :memory_gb, :integer
    end
  end
end
