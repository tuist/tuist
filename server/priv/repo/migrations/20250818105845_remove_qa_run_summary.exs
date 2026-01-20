defmodule Tuist.Repo.Migrations.RemoveQaRunSummary do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    alter table(:qa_runs) do
      remove :summary, :string
    end
  end

  def down do
    alter table(:qa_runs) do
      add :summary, :string
    end
  end
end
