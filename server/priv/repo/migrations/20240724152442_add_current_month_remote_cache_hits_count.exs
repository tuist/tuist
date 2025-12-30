defmodule Tuist.Repo.Migrations.AddCurrentMonthRemoteCacheHitsCount do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add(:current_month_remote_cache_hits_count, :integer, default: 0)
      # Deployments might cause the worker that updates the count to be interrupted.
      # This field makes it possible for the job to be restarted and continue with the remaining accounts.
      add(:current_month_remote_cache_hits_count_updated_at, :naive_datetime, required: false)
    end
  end
end
