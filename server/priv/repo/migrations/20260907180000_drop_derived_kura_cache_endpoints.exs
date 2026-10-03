defmodule Tuist.Repo.Migrations.DropDerivedKuraCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # Cache resolution reads `kura_servers` directly, so these rows are no longer
  # read by anything. `account_cache_endpoints` keeps the two kinds of row that
  # have no other home: the customer's own endpoints (`technology = 0`) and the
  # internal mTLS peer addresses of enrolled self-hosted nodes
  # (`technology = 3`).

  # account_cache_endpoints.technology is an Ecto.Enum stored as an integer
  # (`default: 0`, `kura: 1`, `kura_self_hosted_peer: 3`).
  @kura_technology 1

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DELETE FROM account_cache_endpoints WHERE technology = #{@kura_technology}")
  end

  # The rows were derived from `kura_servers`, which still holds every one of
  # them, so there is nothing here that a rollback would need to restore.
  def down, do: :ok
end
