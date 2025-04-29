defmodule Tuist.Repo.Migrations.DropInsertedAtNaive do
  use Ecto.Migration

  def up do
    alter table(:previews) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :inserted_at_naive
    end
  end

  def down do
    alter table(:previews) do
      add :inserted_at_naive, :naive_datetime
    end
  end
end
