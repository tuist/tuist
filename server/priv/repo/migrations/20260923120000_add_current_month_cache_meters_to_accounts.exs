defmodule Tuist.Repo.Migrations.AddCurrentMonthCacheMetersToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :current_month_cache_egress_megabytes, :bigint, default: 0
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :current_month_cache_requests, :bigint, default: 0
    end
  end
end
