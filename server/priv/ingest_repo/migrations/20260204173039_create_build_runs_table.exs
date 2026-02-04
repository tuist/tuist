defmodule Tuist.IngestRepo.Migrations.CreateBuildRunsTable do
  use Ecto.Migration

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
      `status` Enum8('success' = 0, 'failure' = 1),
      `category` Nullable(Enum8('clean' = 0, 'incremental' = 1)),
      `configuration` Nullable(String),
      `git_branch` Nullable(String),
      `git_commit_sha` Nullable(String),
      `git_ref` Nullable(String),
      `ci_run_id` Nullable(String),
      `ci_project_handle` Nullable(String),
      `ci_host` Nullable(String),
      `ci_provider` Nullable(Enum8('github' = 0, 'gitlab' = 1, 'bitrise' = 2, 'circleci' = 3, 'buildkite' = 4, 'codemagic' = 5)),
      `cacheable_task_remote_hits_count` Int32 DEFAULT 0,
      `cacheable_task_local_hits_count` Int32 DEFAULT 0,
      `cacheable_tasks_count` Int32 DEFAULT 0,
      `custom_tags` Array(String) DEFAULT [],
      `custom_values` Map(String, String) DEFAULT map(),
      `inserted_at` DateTime64(6)
    )
    ENGINE = MergeTree
    PRIMARY KEY (project_id, inserted_at, id)
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
      COALESCE(is_ci, false) as is_ci,
      model_identifier,
      scheme,
      multiIf(status = 0, 'success', status = 1, 'failure', 'success') as status,
      multiIf(category IS NULL, NULL, category = 0, 'clean', category = 1, 'incremental', NULL) as category,
      configuration,
      git_branch,
      git_commit_sha,
      git_ref,
      ci_run_id,
      ci_project_handle,
      ci_host,
      multiIf(
        ci_provider IS NULL, NULL,
        ci_provider = 0, 'github',
        ci_provider = 1, 'gitlab',
        ci_provider = 2, 'bitrise',
        ci_provider = 3, 'circleci',
        ci_provider = 4, 'buildkite',
        ci_provider = 5, 'codemagic',
        NULL
      ) as ci_provider,
      COALESCE(cacheable_task_remote_hits_count, 0) as cacheable_task_remote_hits_count,
      COALESCE(cacheable_task_local_hits_count, 0) as cacheable_task_local_hits_count,
      COALESCE(cacheable_tasks_count, 0) as cacheable_tasks_count,
      COALESCE(custom_tags, []) as custom_tags,
      COALESCE(custom_values, map()) as custom_values,
      inserted_at
    FROM postgresql('#{host}:#{port}', '#{database}', 'build_runs', '#{username}', '#{password}', 'public')
    """)
  end
end
