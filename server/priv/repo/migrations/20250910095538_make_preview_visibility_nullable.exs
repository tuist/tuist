defmodule Tuist.Repo.Migrations.MakePreviewVisibilityNullable do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:previews) do
      modify :visibility, :integer,
        null: true,
        default: nil,
        from: {:integer, null: false, default: 1}
    end
  end
end
