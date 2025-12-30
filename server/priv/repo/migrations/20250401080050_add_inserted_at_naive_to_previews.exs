defmodule Tuist.Repo.Migrations.AddInsertedAtNaiveToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :inserted_at_naive, :timestamptz
    end
  end
end
