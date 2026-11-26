defmodule Tuist.IngestRepo.Migrations.CreateMarketingLandings do
  @moduledoc """
  One row per visit that arrived on a marketing or documentation page from a
  campaign link (UTM parameters) on another site. It holds only the campaign,
  the referring host and the landing path: no IP address, user agent or
  identifier, so a row cannot be tied to a visitor. Atlas counts them as the
  top of its acquisition funnel.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS marketing_landings (
      id UUID,
      source LowCardinality(String),
      medium LowCardinality(String),
      campaign String,
      content String,
      term String,
      referrer_host LowCardinality(String),
      path String,
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("MergeTree")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (inserted_at, source)
    TTL toDateTime(inserted_at) + INTERVAL 730 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS marketing_landings")
  end
end
