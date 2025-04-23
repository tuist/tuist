defmodule Tuist.Repo.Migrations.DropInsertedAtNaive do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :inserted_at_naive
    end
  end
end
