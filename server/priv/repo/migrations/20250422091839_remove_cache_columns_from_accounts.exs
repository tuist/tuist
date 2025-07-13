defmodule Tuist.Repo.Migrations.RemoveCacheColumnsFromAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :cache_download_event_count, :integer, default: 0
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :cache_upload_event_count, :integer, default: 0
    end
  end
end
