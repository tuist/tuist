defmodule Tuist.Repo.Migrations.DropAccountCachedUsageCols do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      remove :current_month_remote_cache_hits_count
      remove :current_month_remote_cache_hits_count_updated_at
    end
  end
end
