defmodule Tuist.Repo.Migrations.ChangePreviewInsertedAtNaiveType do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :inserted_at_naive, :naive_datetime, from: :utc_datetime
    end
  end
end
