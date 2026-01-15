defmodule Tuist.Repo.Migrations.AddQaCredentialsToProjects do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:projects) do
      add :qa_email, :text, default: "", null: false
      add :qa_password, :text, default: "", null: false
    end
  end
end
