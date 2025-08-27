defmodule Tuist.Repo.Migrations.AddFinishedAtToQaRuns do
  use Ecto.Migration

  def change do
    alter table(:qa_runs) do
      add :finished_at, :timestamptz
    end
  end
end
