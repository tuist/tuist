defmodule Tuist.Repo.Migrations.AddSelfHostedPeerSweepIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The stale-peer sweep filters kura_self_hosted_peer rows (technology = 3)
  # by timestamps without an account scope; these partial indexes keep it
  # index-backed as the table grows.
  def change do
    create index(:account_cache_endpoints, [:updated_at],
             where: "technology = 3 AND deactivated_at IS NULL",
             name: :account_cache_endpoints_active_self_hosted_peer_index,
             concurrently: true
           )

    create index(:account_cache_endpoints, [:deactivated_at],
             where: "technology = 3",
             name: :account_cache_endpoints_deactivated_self_hosted_peer_index,
             concurrently: true
           )
  end
end
