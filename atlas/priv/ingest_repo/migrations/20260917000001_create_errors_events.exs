defmodule Atlas.IngestRepo.Migrations.CreateErrorsEvents do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS errors_events (
      event_id           UUID,
      project_id         String,
      domain_id          String,
      issue_id           String,
      fingerprint        FixedString(64),
      timestamp          DateTime64(6, 'UTC'),
      received_at        DateTime64(6, 'UTC') DEFAULT now64(6, 'UTC'),
      platform           LowCardinality(String),
      level              LowCardinality(String),
      environment        LowCardinality(String),
      release            String,
      dist               String,
      server_name        String,
      transaction        String,
      logger             LowCardinality(String),
      exception_type     String,
      exception_value    String,
      top_frame_function String,
      top_frame_module   String,
      top_frame_filename String,
      user_id            String,
      user_email         String,
      user_ip            String,
      request_url        String,
      request_method     LowCardinality(String),
      sdk_name           LowCardinality(String),
      sdk_version        LowCardinality(String),
      tags               Map(LowCardinality(String), String),
      payload            String CODEC(ZSTD(3))
    )
    ENGINE = MergeTree
    PARTITION BY toYYYYMM(timestamp)
    ORDER BY (project_id, fingerprint, timestamp)
    TTL toDateTime(timestamp) + INTERVAL 90 DAY
    SETTINGS index_granularity = 8192
    """)

    execute("""
    ALTER TABLE errors_events
      ADD INDEX IF NOT EXISTS idx_issue_id issue_id TYPE bloom_filter GRANULARITY 1
    """)

    execute("""
    ALTER TABLE errors_events
      ADD INDEX IF NOT EXISTS idx_environment environment TYPE set(64) GRANULARITY 1
    """)

    execute("""
    ALTER TABLE errors_events
      ADD INDEX IF NOT EXISTS idx_release release TYPE bloom_filter GRANULARITY 1
    """)

    execute("""
    ALTER TABLE errors_events
      ADD INDEX IF NOT EXISTS idx_domain_id domain_id TYPE bloom_filter GRANULARITY 1
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS errors_events")
  end
end
