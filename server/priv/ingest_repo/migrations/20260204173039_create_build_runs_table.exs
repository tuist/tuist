defmodule Tuist.IngestRepo.Migrations.CreateBuildRunsTable do
  use Ecto.Migration

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @moduledoc """
  Creates the build_runs table in ClickHouse and backfills data from PostgreSQL.

  This migration moves build_runs from PostgreSQL/TimescaleDB to ClickHouse for analytics.
  The PostgreSQL table is kept for rollback purposes but will no longer be written to.
  """

  def up do
    skip_data_migration? = System.get_env("TUIST_SKIP_DATA_MIGRATION") in ["true", "1"]

    execute("""
    CREATE TABLE IF NOT EXISTS build_runs
    (
      `id` UUID,
      `duration` Int32,
      `project_id` Int64,
      `account_id` Int64,
      `macos_version` Nullable(String),
      `xcode_version` Nullable(String),
      `is_ci` Bool DEFAULT false,
      `model_identifier` Nullable(String),
      `scheme` Nullable(String),
      `status` LowCardinality(String) DEFAULT 'unknown',
      `category` LowCardinality(String) DEFAULT 'unknown',
      `configuration` Nullable(String),
      `git_branch` Nullable(String),
      `git_commit_sha` Nullable(String),
      `git_ref` Nullable(String),
      `ci_run_id` Nullable(String),
      `ci_project_handle` Nullable(String),
      `ci_host` Nullable(String),
      `ci_provider` LowCardinality(String) DEFAULT 'unknown',
      `cacheable_task_remote_hits_count` Int32 DEFAULT 0,
      `cacheable_task_local_hits_count` Int32 DEFAULT 0,
      `cacheable_tasks_count` Int32 DEFAULT 0,
      `custom_tags` Array(String) DEFAULT [],
      `custom_values` Map(String, String) DEFAULT map(),
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, inserted_at, id)
    SETTINGS index_granularity = 8192
    """)

    unless skip_data_migration? do
      backfill_from_postgres()
    end
  end

  def down do
    drop table(:build_runs)
  end

  defp backfill_from_postgres do
    secrets = Tuist.Environment.decrypt_secrets()
    repo_config = Application.get_env(:tuist, Tuist.Repo, [])

    {username, password, host, port, database} =
      if database_url = Tuist.Environment.ipv4_database_url(secrets) do
        uri = URI.parse(database_url)
        [user, pass] = String.split(uri.userinfo || "postgres:postgres", ":")
        db_host = uri.host || "localhost"
        db_port = uri.port || 5432
        db_name = String.trim_leading(uri.path || "/tuist", "/")
        {user, pass, db_host, db_port, db_name}
      else
        db_name =
          case Keyword.get(repo_config, :database) do
            "tuist_test" <> _ = test_db -> test_db <> System.get_env("MIX_TEST_PARTITION", "")
            other -> other || "tuist_development"
          end

        {
          Keyword.get(repo_config, :username),
          Keyword.get(repo_config, :password),
          Keyword.get(repo_config, :hostname, "localhost"),
          Keyword.get(repo_config, :port, 5432),
          db_name
        }
      end

    execute("""
    INSERT INTO build_runs
    SELECT
      id,
      duration,
      project_id,
      account_id,
      macos_version,
      xcode_version,
      coalesce(is_ci, false) AS is_ci,
      model_identifier,
      scheme,
      CASE status WHEN 0 THEN 'success' WHEN 1 THEN 'failure' ELSE 'success' END AS status,
      CASE category WHEN 0 THEN 'clean' WHEN 1 THEN 'incremental' ELSE 'unknown' END AS category,
      configuration,
      git_branch,
      git_commit_sha,
      git_ref,
      ci_run_id,
      ci_project_handle,
      ci_host,
      CASE ci_provider
        WHEN 0 THEN 'github'
        WHEN 1 THEN 'gitlab'
        WHEN 2 THEN 'bitrise'
        WHEN 3 THEN 'circleci'
        WHEN 4 THEN 'buildkite'
        WHEN 5 THEN 'codemagic'
        ELSE 'unknown'
      END AS ci_provider,
      coalesce(cacheable_task_remote_hits_count, 0) AS cacheable_task_remote_hits_count,
      coalesce(cacheable_task_local_hits_count, 0) AS cacheable_task_local_hits_count,
      coalesce(cacheable_tasks_count, 0) AS cacheable_tasks_count,
      arrayMap(x -> assumeNotNull(x), arrayFilter(x -> x IS NOT NULL, ifNull(custom_tags, []))) AS custom_tags,
      JSONExtract(ifNull(custom_values, '{}'), 'Map(String, String)') AS custom_values,
      inserted_at
    FROM postgresql('#{host}:#{port}', '#{database}', 'build_runs', '#{username}', '#{password}')
    """)

    Logger.info("Backfill complete")
  end
end
