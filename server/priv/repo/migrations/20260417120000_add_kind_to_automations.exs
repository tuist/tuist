defmodule Tuist.Repo.Migrations.AddKindToAutomations do
  use Ecto.Migration

  def change do
    alter table(:automations) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :kind, :string, null: false, default: "alert"
    end
  end
end
