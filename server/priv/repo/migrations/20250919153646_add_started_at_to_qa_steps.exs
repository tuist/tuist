defmodule Tuist.Repo.Migrations.AddStartedAtToQaSteps do
  use Ecto.Migration

  def change do
    alter table(:qa_steps) do
      add :started_at, :timestamptz
    end
  end
end
