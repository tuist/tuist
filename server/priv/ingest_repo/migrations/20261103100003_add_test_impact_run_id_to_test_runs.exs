defmodule Tuist.IngestRepo.Migrations.AddTestImpactRunIdToTestRuns do
  @moduledoc """
  `test_impact_run_id` on test runs: the impact run coverage-based test
  selection created for the invocation (`test_impact_runs`), set at ingestion
  the way `shard_plan_id` is, on fallbacks too. It sits on the test run because
  the impact run is written before any test run exists.

  Version-1 sharded runs report through `shard_test_reports`, so the column goes
  there too, and the views that merge both into `Tuist.Tests.Test` reads
  (`latest_shard_test_reports`, `reported_test_run_summaries`,
  `test_run_summaries`) are recreated with it, the way
  `CreateImmutableShardReports` built them. A shard's reports keep the latest
  non-null id.
  """
  use Ecto.Migration

  @columns [
    id: "UUID",
    project_id: "Int64",
    duration: "Int32",
    macos_version: "String",
    xcode_version: "String",
    is_ci: "Bool",
    model_identifier: "String",
    scheme: "String",
    status: "LowCardinality(String)",
    git_branch: "String",
    git_commit_sha: "String",
    git_ref: "String",
    account_id: "Int64",
    actor_account_id: "Int64",
    claimed_actor_id: "String",
    submission_auth: "LowCardinality(String)",
    ran_at: "DateTime64(6)",
    inserted_at: "DateTime64(6)",
    ci_run_id: "String",
    ci_project_handle: "String",
    ci_host: "String",
    ci_provider: "LowCardinality(Nullable(String))",
    build_run_id: "Nullable(UUID)",
    is_flaky: "Bool",
    build_system: "LowCardinality(String)",
    gradle_build_id: "Nullable(UUID)",
    shard_plan_id: "Nullable(UUID)",
    only_test_identifiers: "Array(String)",
    skip_test_identifiers: "Array(String)",
    stress_mode: "LowCardinality(String)",
    stress_outcome: "LowCardinality(String)",
    stress_skip_reason: "String",
    stress_new_count: "UInt32",
    stress_stressed_count: "UInt32",
    stress_excluded_count: "UInt32",
    stress_known_count: "UInt32",
    bazel_invocation_id: "String",
    base_branch: "String",
    merge_base_sha: "String",
    is_pull_request: "Bool",
    pull_request_number: "UInt32",
    git_object_format: "LowCardinality(String)",
    history_source: "LowCardinality(String)",
    history_fallback_reason: "String",
    git_repository_id: "Int64",
    git_dirty: "Bool",
    execution_mode: "LowCardinality(String)",
    coverage_evidence_status: "LowCardinality(String)",
    once_run_id: "String",
    coverage_enabled: "Nullable(Bool)",
    reporting_version: "UInt8",
    test_impact_run_id: "Nullable(UUID)"
  ]
  @previous_columns Keyword.delete(@columns, :test_impact_run_id)
  @group_fields [:project_id, :ran_at, :id]
  @actor_fields [:actor_account_id, :claimed_actor_id, :submission_auth]
  @stress_counts [:stress_new_count, :stress_stressed_count, :stress_excluded_count]
  @order "tuple(shard_attempt, report_phase, shard_report_revision, report_digest)"

  def up do
    alter table(:test_runs), do: add(:test_impact_run_id, :"Nullable(UUID)")
    alter table(:shard_test_reports), do: add(:test_impact_run_id, :"Nullable(UUID)")
    create_views(@columns)
  end

  def down do
    create_views(@previous_columns)
    alter table(:shard_test_reports), do: remove(:test_impact_run_id)
    alter table(:test_runs), do: remove(:test_impact_run_id)
  end

  defp create_views(columns) do
    cohort_columns =
      Enum.map_join(columns, ",\n", fn {name, type} ->
        expression =
          cond do
            name in @group_fields -> to_string(name)
            name in [:inserted_at, :is_flaky] -> "max(#{name})"
            name in @actor_fields -> "tupleElement(argMax(tuple(#{name}), #{@order}), 1)"
            true -> latest(name, type, @order)
          end

        "#{expression} AS #{name}"
      end)

    selected_columns =
      Enum.map_join(columns, ",\n", fn {name, _type} ->
        expression =
          cond do
            name in @group_fields -> "c.#{name}"
            name == :inserted_at -> "max(c.#{name})"
            true -> "tupleElement(argMax(tuple(c.#{name}), c.report_order), 1)"
          end

        "#{expression} AS #{name}"
      end)

    execute """
    CREATE OR REPLACE VIEW latest_shard_test_reports AS
    SELECT #{selected_columns}, c.shard_index AS shard_index, max(c.shard_count) AS shard_count,
      max(c.report_order) AS report_order,
      argMax(c.fact_set_id, c.report_order) AS fact_set_id,
      argMax(c.source_test_run_id, c.report_order) AS source_test_run_id,
      argMax(c.execution_started_at, c.report_order) AS execution_started_at
    FROM (
      SELECT #{cohort_columns}, shard_index, max(shard_count) AS shard_count,
        max(#{@order}) AS report_order,
        argMax(fact_set_id, #{@order}) AS fact_set_id,
        argMax(source_test_run_id, #{@order}) AS source_test_run_id,
        argMax(execution_started_at, #{@order}) AS execution_started_at
      FROM shard_test_reports
      GROUP BY project_id, ran_at, id, shard_index, shard_attempt, shard_report_revision
    ) AS c
    GROUP BY c.project_id, c.ran_at, c.id, c.shard_index
    """

    summary_columns =
      Enum.map_join(columns, ",\n", fn {name, type} ->
        expression =
          cond do
            name in @group_fields ->
              to_string(name)

            name == :status ->
              merged_status()

            name in @actor_fields ->
              "tupleElement(argMax(tuple(r.#{name}), r.report_order), 1)"

            name in [:duration, :inserted_at, :is_flaky, :git_dirty, :stress_known_count] ->
              "max(r.#{name})"

            name in @stress_counts ->
              "toUInt32(sum(r.#{name}))"

            name in [:only_test_identifiers, :skip_test_identifiers] ->
              "arrayDistinct(arrayFlatten(groupArray(r.#{name})))"

            name == :stress_outcome ->
              severity("r.#{name}", ["", "no_candidates", "passed", "skipped", "disagreed"])

            name == :coverage_evidence_status ->
              severity("r.#{name}", ["", "not_linked", "failed", "collected"])

            true ->
              latest(name, type, "r.report_order", "r.")
          end

        "#{expression} AS #{name}"
      end)

    fields = Enum.map_join(columns, ", ", fn {name, _} -> to_string(name) end)

    execute """
    CREATE OR REPLACE VIEW reported_test_run_summaries AS
    SELECT #{summary_columns}
    FROM latest_shard_test_reports AS r
    GROUP BY project_id, ran_at, id
    """

    execute """
    CREATE OR REPLACE VIEW test_run_summaries AS
    SELECT #{fields} FROM test_runs FINAL
    UNION ALL
    SELECT #{fields} FROM reported_test_run_summaries
    """
  end

  defp latest(name, type, order, prefix \\ "") do
    column = "#{prefix}#{name}"

    condition =
      cond do
        String.contains?(type, "Nullable") ->
          "#{column} IS NOT NULL"

        String.contains?(type, "String") or String.starts_with?(type, "Array") ->
          "notEmpty(#{column})"

        name in @stress_counts or name == :stress_known_count ->
          "#{column} > 0"

        true ->
          nil
      end

    if condition do
      "tupleElement(argMaxIf(tuple(#{column}), #{order}, #{condition}), 1)"
    else
      "tupleElement(argMax(tuple(#{column}), #{order}), 1)"
    end
  end

  defp merged_status do
    """
    multiIf(
      countIf(r.status = 'failed_processing') > 0, 'failed_processing',
      countIf(r.status = 'failure') > 0, 'failure',
      countIf(r.status NOT IN ('processing', 'in_progress')) = max(r.shard_count), if(max(r.shard_count) = 1, any(r.status), 'success'),
      max(r.inserted_at) < now64(6) - INTERVAL 6 HOUR, 'failure',
      if(max(r.shard_count) = 1, any(r.status), 'in_progress')
    )
    """
  end

  defp severity(name, values) do
    array = "[" <> Enum.map_join(values, ",", &("'" <> &1 <> "'")) <> "]"
    "arrayElement(#{array}, max(indexOf(#{array}, #{name})))"
  end
end
