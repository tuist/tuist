defmodule Tuist.Repo.Migrations.AddOnceActionHistoryIdentity do
  use Ecto.Migration

  def change do
    alter table(:once_actions) do
      add :history_id, :uuid
      add :history_namespace, :string
      add :history_key, :string
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :history_ambiguous, :boolean, default: false, null: false
    end
  end
end
