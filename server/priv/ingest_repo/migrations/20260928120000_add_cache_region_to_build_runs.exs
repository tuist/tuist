defmodule Tuist.IngestRepo.Migrations.AddCacheRegionToBuildRuns do
  use Ecto.Migration

  # Where a build came from and which cache region served it. A managed
  # account's stable hostname is routed by the client's resolver, so a VPN or
  # corporate resolver can send a build to a far region. Region and origin
  # labels only: no addresses.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE build_runs
      ADD COLUMN IF NOT EXISTS `client_origin` LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS `cache_serving_region` LowCardinality(String) DEFAULT ''
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE build_runs
      DROP COLUMN IF EXISTS `client_origin`,
      DROP COLUMN IF EXISTS `cache_serving_region`
    """)
  end
end
