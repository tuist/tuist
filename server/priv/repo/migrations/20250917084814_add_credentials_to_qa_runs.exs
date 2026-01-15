defmodule Tuist.Repo.Migrations.AddCredentialsToQaRuns do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:qa_runs) do
      add :email, :text, default: "", null: false
      add :password, :text, default: "", null: false
    end
  end
end
