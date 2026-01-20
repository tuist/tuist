defmodule Tuist.Repo.Migrations.AddAppDescriptionToQaRuns do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:qa_runs) do
      add :app_description, :text, default: "", null: false
    end
  end
end
