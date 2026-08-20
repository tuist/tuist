defmodule Tuist.Repo.Migrations.AddAccountsVisibility do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :visibility, :integer, null: false, default: 0
    end
  end
end
