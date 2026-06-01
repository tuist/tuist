defmodule Tuist.Repo.Migrations.RemoveKuraAccountLevelCacheEndpoints do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM account_cache_endpoints AS endpoint
    USING accounts AS account
    WHERE endpoint.account_id = account.id
      AND endpoint.technology = 1
      AND endpoint.url = 'https://' || lower(account.name) || '.kura.tuist.dev'
    """)
  end

  def down do
    :ok
  end
end
