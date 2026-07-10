defmodule Tuist.ClickHouseRetention do
  @moduledoc false

  alias Tuist.IngestRepo

  require Logger

  @column_preferences [
    "inserted_at",
    "ran_at",
    "created_at",
    "updated_at",
    "enqueued_at",
    "date",
    "day",
    "window_start",
    "timestamp",
    "ts"
  ]

  @domains %{
    automations: [
      "automation_alert_events"
    ],
    builds: [
      "build_runs",
      "build_issues",
      "build_files",
      "build_targets",
      "build_machine_metrics",
      "cacheable_tasks",
      "cas_outputs"
    ],
    bundles: [
      "bundles",
      "artifacts"
    ],
    cache: [
      "cas_entries",
      "cas_events",
      "cas_events_daily_stats",
      "module_cache_outputs"
    ],
    command_events: [
      "command_events",
      "command_events_by_ran_at",
      "command_events_by_duration",
      "command_events_by_hit_rate"
    ],
    gradle: [
      "gradle_builds",
      "gradle_tasks",
      "gradle_cache_events"
    ],
    kura: [
      "kura_usage_events"
    ],
    qa: [
      "qa_logs"
    ],
    registry: [
      "registry_download_events"
    ],
    runners: [
      "runner_jobs",
      "runner_job_steps",
      "runner_job_logs",
      "runner_job_machine_metrics"
    ],
    shards: [
      "shard_plans",
      "shard_plan_modules",
      "shard_plan_test_suites",
      "shard_runs"
    ],
    tests: [
      "test_runs",
      "test_cases",
      "test_case_runs",
      "test_module_runs",
      "test_suite_runs",
      "test_case_failures",
      "test_case_events",
      "test_case_run_repetitions",
      "test_case_run_attachments",
      "test_case_run_crash_reports",
      "test_case_run_arguments",
      "test_run_destinations",
      "test_run_errors",
      "test_case_runs_by_inserted_at",
      "test_case_runs_daily_stats",
      "test_case_runs_dashboard_count",
      "test_case_branch_presence",
      "flaky_test_case_runs",
      "test_case_runs_by_test_run",
      "test_case_runs_by_shard_id",
      "test_case_runs_by_commit",
      "test_case_runs_by_project",
      "test_case_runs_active_daily_stats",
      "test_case_run_daily_stats_per_case",
      "test_case_runs_recent_per_case",
      "test_case_runs_validated_on_branch"
    ],
    webhooks: [
      "webhook_delivery_attempts"
    ],
    xcode: [
      "xcode_graphs",
      "xcode_projects",
      "xcode_targets",
      "xcode_targets_denormalized"
    ]
  }

  @domain_env_names %{
    automations: "AUTOMATIONS",
    builds: "BUILDS",
    bundles: "BUNDLES",
    cache: "CACHE",
    command_events: "COMMAND_EVENTS",
    gradle: "GRADLE",
    kura: "KURA",
    qa: "QA",
    registry: "REGISTRY",
    runners: "RUNNERS",
    shards: "SHARDS",
    tests: "TESTS",
    webhooks: "WEBHOOKS",
    xcode: "XCODE"
  }

  def apply_configured_retention(repo \\ IngestRepo, env \\ System.get_env()) do
    targets = configured_targets(env)

    Enum.each(targets, &apply_retention(repo, &1))

    :ok
  end

  def configured_targets(env \\ System.get_env()) do
    default_days =
      env
      |> retention_setting!("TUIST_CLICKHOUSE_RETENTION_DEFAULT_DAYS")
      |> resolve_days(nil)

    table_overrides = table_overrides!(env)

    @domains
    |> Enum.sort_by(fn {domain, _tables} -> domain end)
    |> Enum.flat_map(fn {domain, tables} ->
      domain_days =
        env
        |> retention_setting!(domain_env_name(domain))
        |> resolve_days(default_days)

      tables
      |> Enum.sort()
      |> Enum.flat_map(fn table ->
        days = table_overrides |> Map.get(table, :unset) |> resolve_days(domain_days)

        if is_integer(days) do
          [%{domain: domain, table: table, columns: @column_preferences, days: days}]
        else
          []
        end
      end)
    end)
  end

  def domain_env_names do
    @domain_env_names
  end

  def known_table_names do
    @domains
    |> Map.values()
    |> List.flatten()
    |> MapSet.new()
  end

  def alter_table_statement(table, column, days) do
    "ALTER TABLE #{quote_identifier!(table)} MODIFY TTL #{quote_identifier!(column)} + INTERVAL #{days} DAY DELETE"
  end

  defp apply_retention(repo, target) do
    case ttl_column(repo, target) do
      {:ok, column} ->
        repo.query!(alter_table_statement(target.table, column, target.days))

        Logger.info("Applied ClickHouse #{target.domain} retention to #{target.table}: #{target.days} days")

      :skip ->
        Logger.debug("Skipped ClickHouse retention for #{target.table}")
    end
  end

  defp ttl_column(repo, target) do
    with true <- merge_tree_table?(repo, target.table),
         {:ok, columns} <- table_columns(repo, target.table),
         column when is_binary(column) <- Enum.find(target.columns, &MapSet.member?(columns, &1)) do
      {:ok, column}
    else
      _ -> :skip
    end
  end

  defp merge_tree_table?(repo, table) do
    case repo.query(
           """
           SELECT engine
           FROM system.tables
           WHERE database = currentDatabase() AND name = {table:String}
           """,
           %{table: table}
         ) do
      {:ok, %{rows: [[engine]]}} -> String.contains?(engine, "MergeTree")
      {:ok, %{rows: []}} -> false
    end
  end

  defp table_columns(repo, table) do
    {:ok, %{rows: rows}} =
      repo.query(
        """
        SELECT name
        FROM system.columns
        WHERE database = currentDatabase() AND table = {table:String}
        """,
        %{table: table}
      )

    {:ok, MapSet.new(rows, fn [name] -> name end)}
  end

  defp retention_setting!(env, env_name), do: parse_retention_setting!(Map.get(env, env_name), env_name)

  defp parse_retention_setting!(nil, _env_name), do: :unset
  defp parse_retention_setting!("", _env_name), do: :unset
  defp parse_retention_setting!(false, _env_name), do: :disabled
  defp parse_retention_setting!(0, _env_name), do: :disabled

  defp parse_retention_setting!(value, _env_name) when is_integer(value) and value > 0 do
    {:days, value}
  end

  defp parse_retention_setting!(value, env_name) when is_binary(value) do
    value = String.trim(value)

    cond do
      value in ["", "0", "disabled", "false", "none", "off"] ->
        :disabled

      String.match?(value, ~r/^[1-9][0-9]*$/) ->
        {:days, String.to_integer(value)}

      true ->
        raise ArgumentError, "#{env_name} must be a positive integer number of days, 0, or empty"
    end
  end

  defp parse_retention_setting!(_value, env_name) do
    raise ArgumentError, "#{env_name} must be a positive integer number of days, 0, or empty"
  end

  defp resolve_days({:days, days}, _fallback), do: days
  defp resolve_days(:disabled, _fallback), do: nil
  defp resolve_days(:unset, fallback), do: fallback

  defp table_overrides!(env) do
    case Map.get(env, "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON") do
      value when value in [nil, ""] ->
        %{}

      value ->
        value
        |> Jason.decode!()
        |> parse_table_overrides!()
    end
  end

  defp parse_table_overrides!(overrides) when is_map(overrides) do
    known_table_names = known_table_names()

    Map.new(overrides, fn {table, value} ->
      if !MapSet.member?(known_table_names, table) do
        raise ArgumentError, "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON contains unknown table #{inspect(table)}"
      end

      {table, parse_retention_setting!(value, "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON[#{table}]")}
    end)
  end

  defp parse_table_overrides!(_overrides) do
    raise ArgumentError, "TUIST_CLICKHOUSE_RETENTION_TABLES_JSON must be a JSON object"
  end

  defp domain_env_name(domain) do
    "TUIST_CLICKHOUSE_RETENTION_#{Map.fetch!(@domain_env_names, domain)}_DAYS"
  end

  defp quote_identifier!(identifier) do
    if String.match?(identifier, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/) do
      "`#{identifier}`"
    else
      raise ArgumentError, "invalid ClickHouse identifier #{inspect(identifier)}"
    end
  end
end
