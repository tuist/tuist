defmodule Tuist.Repo.Migrations.AddArchiveToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :bundle_identifier, :string
      add :version, :string
      add :type, :integer
    end
  end
end
