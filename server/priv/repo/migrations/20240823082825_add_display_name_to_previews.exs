defmodule Tuist.Repo.Migrations.AddDisplayNameToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :display_name, :string, null: true
    end
  end
end
