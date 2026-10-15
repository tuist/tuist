defmodule Tuist.IngestRepo.Migrations.CreateBuildEntityTables do
  @moduledoc """
  Stable, project-scoped build entities (Gradle tasks, Xcode modules and cache
  actions, Bazel cache actions, Once actions, Mix files and modules) and one
  slim observation per execution of each.

  `build_entity_observations` is the only write path. Producers compute
  `entity_id` and `id` deterministically in process (`Tuist.BuildEntities.Identity`),
  so a retried build, a replayed Once batch or a duplicate webhook produces
  identical rows that ReplacingMergeTree collapses. Readers deduplicate by `id`
  before aggregating, so unmerged duplicates never bias distributions.

  The sort key leads with the entity and stable observation ID, so FINAL
  resolves complete replacement rows in a sorted stream without a per-observation
  argMax state table. Observation time is not in the replacement key: a replay correcting
  its time replaces the old version. Time/cohort filters must run after latest
  resolution anyway. Branch, environment, commit and parent IDs are
  denormalized so analytics need no native-table joins.

  `build_entities` is maintained by `build_entities_mv`. Every aggregate it
  holds is insensitive to duplicates: identity is a pure function of
  `entity_id` (`any`), the display name is the one from the latest *observed*
  execution (`argMax` on `observed_at`, so a delayed report cannot overwrite a
  newer label), and first/last seen are `min`/`max`.

  Retention follows the native source: 30 days for Xcode modules (the source
  `xcode_targets` TTL) and 90 days for everything else. Catalog rows expire
  after 365 days without an observation.

  There is deliberately no distribution rollup: a materialized `sum`/`avg`/
  `quantiles` state double counts retried inserts.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS build_entity_observations (
      project_id Int64,
      system LowCardinality(String),
      kind LowCardinality(String),
      entity_id UUID,
      observed_at DateTime64(6),
      id UUID,
      name String,
      identity String,
      parent_id String,
      execution_id String,
      status LowCardinality(String),
      cache_status LowCardinality(String),
      duration_ms Nullable(UInt64),
      git_branch String,
      git_commit_sha String,
      is_ci Nullable(Bool),
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, system, kind, entity_id, id)
    TTL addDays(toDateTime(inserted_at), if(system = 'xcode' AND kind = 'module', 30, 90))
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS build_entities (
      project_id Int64,
      system LowCardinality(String),
      kind LowCardinality(String),
      entity_id UUID,
      identity SimpleAggregateFunction(any, String),
      name AggregateFunction(argMax, String, DateTime64(6)),
      first_seen_at SimpleAggregateFunction(min, DateTime64(6)),
      last_seen_at SimpleAggregateFunction(max, DateTime64(6))
    ) ENGINE = #{Migration.engine("AggregatingMergeTree")}
    ORDER BY (project_id, system, kind, entity_id)
    TTL toDateTime(last_seen_at) + INTERVAL 365 DAY
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS build_entities_mv
    TO build_entities AS
    SELECT
      project_id,
      system,
      kind,
      entity_id,
      any(identity) AS identity,
      argMaxState(name, observed_at) AS name,
      min(observed_at) AS first_seen_at,
      max(observed_at) AS last_seen_at
    FROM build_entity_observations
    GROUP BY project_id, system, kind, entity_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS build_entities_mv")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS build_entities")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS build_entity_observations")
  end
end
