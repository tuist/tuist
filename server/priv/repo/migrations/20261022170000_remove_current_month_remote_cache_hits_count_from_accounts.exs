defmodule Tuist.Repo.Migrations.RemoveCurrentMonthRemoteCacheHitsCountFromAccounts do
  use Ecto.Migration

  def up do
    alter table(:accounts) do
      # No code reads or writes the counter, and the organizations API reports
      # remote cache hits as 0 without it.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :current_month_remote_cache_hits_count
    end
  end

  def down do
    alter table(:accounts) do
      # PostgreSQL 16 stores this constant default without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :current_month_remote_cache_hits_count, :integer, default: 0
    end
  end
end
