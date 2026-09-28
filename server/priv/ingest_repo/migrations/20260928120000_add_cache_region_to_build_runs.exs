defmodule Tuist.IngestRepo.Migrations.AddCacheRegionToBuildRuns do
  use Ecto.Migration

  # Where a build came from, which region served its cache traffic, and which
  # region should have. A managed account's stable hostname is routed by the
  # client's resolver, so a VPN or corporate resolver can send a build to a far
  # region; these let the build report and a per-account metric say so instead
  # of support inferring it from Kura read counters. Region and origin labels
  # only: no addresses.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE build_runs
      ADD COLUMN IF NOT EXISTS `client_origin` LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS `cache_expected_region` LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS `cache_serving_region` LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS `cache_serving_node` String DEFAULT '',
      ADD COLUMN IF NOT EXISTS `cache_serving_region_requests` UInt32 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS `cache_observed_requests` UInt32 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS `cache_connected_at` Nullable(DateTime64(3)),
      ADD COLUMN IF NOT EXISTS `cache_connected_before_build_seconds` Nullable(UInt32)
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE build_runs
      DROP COLUMN IF EXISTS `client_origin`,
      DROP COLUMN IF EXISTS `cache_expected_region`,
      DROP COLUMN IF EXISTS `cache_serving_region`,
      DROP COLUMN IF EXISTS `cache_serving_node`,
      DROP COLUMN IF EXISTS `cache_serving_region_requests`,
      DROP COLUMN IF EXISTS `cache_observed_requests`,
      DROP COLUMN IF EXISTS `cache_connected_at`,
      DROP COLUMN IF EXISTS `cache_connected_before_build_seconds`
    """)
  end
end
