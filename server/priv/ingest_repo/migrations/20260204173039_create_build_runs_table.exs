defmodule Tuist.IngestRepo.Migrations.CreateBuildRunsTable do
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @batch_size 10_000
  @throttle_ms 200

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
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, id)
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

    {:ok, pg_conn} =
      Postgrex.start_link(
        hostname: host,
        port: port,
        database: database,
        username: username,
        password: password,
        json_library: Jason,
        backoff_type: :stop
      )

    try do
      do_backfill(pg_conn, DateTime.from_unix!(0), "00000000-0000-0000-0000-000000000000", 0)
    after
      GenServer.stop(pg_conn)
    end
  end

  defp do_backfill(pg_conn, last_inserted_at, last_id, total_inserted) do
    {rows, next_cursor} = fetch_batch(pg_conn, last_inserted_at, last_id)

    case rows do
      [] ->
        Logger.info("Backfill complete (inserted #{total_inserted} row(s) into ClickHouse)")
        :ok

      rows ->
        {next_inserted_at, next_id} = next_cursor

        {inserted_count, _} =
          IngestRepo.insert_all("build_runs", rows,
            types: %{
              id: "UUID",
              duration: "Int32",
              project_id: "Int64",
              account_id: "Int64",
              macos_version: "Nullable(String)",
              xcode_version: "Nullable(String)",
              is_ci: "Bool",
              model_identifier: "Nullable(String)",
              scheme: "Nullable(String)",
              status: "Enum8('success' = 0, 'failure' = 1)",
              category: "Nullable(Enum8('clean' = 0, 'incremental' = 1))",
              configuration: "Nullable(String)",
              git_branch: "Nullable(String)",
              git_commit_sha: "Nullable(String)",
              git_ref: "Nullable(String)",
              ci_run_id: "Nullable(String)",
              ci_project_handle: "Nullable(String)",
              ci_host: "Nullable(String)",
              ci_provider:
                "Nullable(Enum8('github' = 0, 'gitlab' = 1, 'bitrise' = 2, 'circleci' = 3, 'buildkite' = 4, 'codemagic' = 5))",
              cacheable_task_remote_hits_count: "Int32",
              cacheable_task_local_hits_count: "Int32",
              cacheable_tasks_count: "Int32",
              custom_tags: "Array(String)",
              custom_values: "Map(String, String)",
              inserted_at: "DateTime64(6)"
            },
            timeout: :infinity
          )

        Logger.info("Inserted #{inserted_count} build run row(s) into ClickHouse")

        Process.sleep(@throttle_ms)
        do_backfill(pg_conn, next_inserted_at, next_id, total_inserted + inserted_count)
    end
  end

  defp fetch_batch(pg_conn, last_inserted_at, last_id) do
    {:ok, %Postgrex.Result{rows: rows}} =
      Postgrex.query(
        pg_conn,
        """
        SELECT
          id,
          duration,
          project_id,
          account_id,
          macos_version,
          xcode_version,
          is_ci,
          model_identifier,
          scheme,
          status,
          category,
          configuration,
          git_branch,
          git_commit_sha,
          git_ref,
          ci_run_id,
          ci_project_handle,
          ci_host,
          ci_provider,
          cacheable_task_remote_hits_count,
          cacheable_task_local_hits_count,
          cacheable_tasks_count,
          custom_tags,
          custom_values::text,
          inserted_at
        FROM build_runs
        WHERE inserted_at > $1 OR (inserted_at = $1 AND id::text > $2)
        ORDER BY inserted_at, id
        LIMIT $3
        """,
        [last_inserted_at, last_id, @batch_size],
        timeout: :infinity
      )

    mapped = Enum.map(rows, &postgres_row_to_clickhouse_row/1)

    next_cursor =
      case rows do
        [] ->
          {last_inserted_at, last_id}

        _ ->
          last = List.last(rows)
          {inserted_at, id} = {List.last(last), hd(last)}
          {to_datetime(inserted_at), uuid_to_string(id)}
      end

    {mapped, next_cursor}
  end

  defp postgres_row_to_clickhouse_row([
         id,
         duration,
         project_id,
         account_id,
         macos_version,
         xcode_version,
         is_ci,
         model_identifier,
         scheme,
         status,
         category,
         configuration,
         git_branch,
         git_commit_sha,
         git_ref,
         ci_run_id,
         ci_project_handle,
         ci_host,
         ci_provider,
         cacheable_task_remote_hits_count,
         cacheable_task_local_hits_count,
         cacheable_tasks_count,
         custom_tags,
         custom_values_json,
         inserted_at
       ]) do
    %{
      id: uuid_to_string(id),
      duration: duration,
      project_id: project_id,
      account_id: account_id,
      macos_version: macos_version,
      xcode_version: xcode_version,
      is_ci: is_ci || false,
      model_identifier: model_identifier,
      scheme: scheme,
      status: normalize_status(status),
      category: normalize_category(category),
      configuration: configuration,
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
      git_ref: git_ref,
      ci_run_id: ci_run_id,
      ci_project_handle: ci_project_handle,
      ci_host: ci_host,
      ci_provider: normalize_ci_provider(ci_provider),
      cacheable_task_remote_hits_count: cacheable_task_remote_hits_count || 0,
      cacheable_task_local_hits_count: cacheable_task_local_hits_count || 0,
      cacheable_tasks_count: cacheable_tasks_count || 0,
      custom_tags: normalize_custom_tags(custom_tags),
      custom_values: normalize_custom_values(custom_values_json),
      inserted_at: to_naive_datetime(inserted_at)
    }
  end

  defp normalize_status(0), do: "success"
  defp normalize_status(1), do: "failure"
  defp normalize_status("success"), do: "success"
  defp normalize_status("failure"), do: "failure"
  defp normalize_status(_), do: "success"

  defp normalize_category(nil), do: nil
  defp normalize_category(0), do: "clean"
  defp normalize_category(1), do: "incremental"
  defp normalize_category("clean"), do: "clean"
  defp normalize_category("incremental"), do: "incremental"
  defp normalize_category(_), do: nil

  defp normalize_ci_provider(nil), do: nil
  defp normalize_ci_provider(0), do: "github"
  defp normalize_ci_provider(1), do: "gitlab"
  defp normalize_ci_provider(2), do: "bitrise"
  defp normalize_ci_provider(3), do: "circleci"
  defp normalize_ci_provider(4), do: "buildkite"
  defp normalize_ci_provider(5), do: "codemagic"
  defp normalize_ci_provider(provider) when is_binary(provider), do: provider
  defp normalize_ci_provider(_), do: nil

  defp normalize_custom_tags(nil), do: []
  defp normalize_custom_tags(tags) when is_list(tags), do: Enum.filter(tags, &is_binary/1)
  defp normalize_custom_tags(_), do: []

  defp normalize_custom_values(nil), do: %{}
  defp normalize_custom_values(""), do: %{}

  defp normalize_custom_values(values_json) when is_binary(values_json) do
    case Jason.decode(values_json) do
      {:ok, values} when is_map(values) ->
        for {k, v} <- values, is_binary(k) and is_binary(v), into: %{} do
          {k, v}
        end

      _ ->
        %{}
    end
  end

  defp normalize_custom_values(_), do: %{}

  defp to_naive_datetime(%NaiveDateTime{} = ndt), do: ensure_microsecond_precision(ndt)

  defp to_naive_datetime(%DateTime{} = dt),
    do: dt |> DateTime.to_naive() |> ensure_microsecond_precision()

  defp to_naive_datetime(_), do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_datetime(_), do: DateTime.from_unix!(0)

  defp ensure_microsecond_precision(%NaiveDateTime{} = ndt) do
    %{ndt | microsecond: {elem(ndt.microsecond, 0), 6}}
  end

  defp uuid_to_string(<<_::128>> = uuid_bin), do: Ecto.UUID.load!(uuid_bin)
  defp uuid_to_string(uuid) when is_binary(uuid), do: uuid
  defp uuid_to_string(_), do: "00000000-0000-0000-0000-000000000000"
end
