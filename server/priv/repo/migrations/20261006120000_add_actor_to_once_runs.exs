defmodule Tuist.Repo.Migrations.AddActorToOnceRuns do
  use Ecto.Migration

  def change do
    alter table(:once_runs) do
      add :account_id, :bigint
    end
  end
end
