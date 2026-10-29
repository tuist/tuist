defmodule Tuist.IngestRepo.Migrations.CreateImmutableShardReports do
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

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
    reporting_version: "UInt8"
  ]
  @fact_tables [
    {"test_case_runs", true, true},
    {"test_module_runs", true, true},
    {"test_suite_runs", true, true},
    {"test_run_errors", false, true},
    {"test_run_destinations", false, false},
    {"test_run_stress_candidates", false, true}
  ]
  @child_tables ~w(test_case_failures test_case_run_arguments test_case_run_repetitions test_case_run_attachments)
  @group_fields [:project_id, :ran_at, :id]
  @actor_fields [:actor_account_id, :claimed_actor_id, :submission_auth]
  @stress_counts [:stress_new_count, :stress_stressed_count, :stress_excluded_count]
  @order "tuple(shard_attempt, report_phase, shard_report_revision, report_digest)"

  def up do
    pin_case_history_projection()

    alter table(:shard_plans) do
      add :reporting_version, :UInt8, default: 0
      add :assignments, :String, default: ""
    end

    alter table(:test_runs) do
      add :reporting_version, :UInt8, default: 0
    end

    create table(:shard_test_reports,
             primary_key: false,
             engine: Migration.engine("MergeTree"),
             options:
               "PARTITION BY toYYYYMM(ran_at) ORDER BY (project_id, ran_at, id, shard_index)"
           ) do
      for {name, type} <- @columns, do: add(name, String.to_atom(type))
      add :fact_set_id, :UUID
      add :source_test_run_id, :String
      add :shard_index, :UInt16
      add :shard_count, :UInt16
      add :shard_attempt, :UInt32
      add :shard_report_revision, :UInt32
      add :report_phase, :UInt8
      add :report_digest, :String
      add :execution_started_at, :"DateTime64(6)"
    end

    execute "ALTER TABLE shard_test_reports ADD PROJECTION proj_by_id (SELECT * ORDER BY (id, shard_index))"

    for {name, _, _} <- @fact_tables do
      alter table(name), do: add(:shard_report_id, :"Nullable(UUID)")
    end

    cohort_columns =
      Enum.map_join(@columns, ",\n", fn {name, type} ->
        expression =
          cond do
            name in @group_fields -> to_string(name)
            name in [:inserted_at, :is_flaky] -> "max(#{name})"
            name in @actor_fields -> "tupleElement(argMax(tuple(#{name}), #{@order}), 1)"
            true -> latest(name, type, @order)
          end

        "#{expression} AS #{name}"
      end)

    # Fill processing metadata only within one attempt/revision. Then select
    # the cohort by the original phase-before-revision order, preserving empty
    # values in a new execution or terminal correction instead of reviving old ones.
    selected_columns =
      Enum.map_join(@columns, ",\n", fn {name, _type} ->
        expression =
          cond do
            name in @group_fields -> "c.#{name}"
            name == :inserted_at -> "max(c.#{name})"
            true -> "tupleElement(argMax(tuple(c.#{name}), c.report_order), 1)"
          end

        "#{expression} AS #{name}"
      end)

    execute """
    CREATE VIEW latest_shard_test_reports AS
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

    # Create the latest-report view before the current-fact views that select
    # its fact sets.
    for {name, replacing?, project?} <- @fact_tables do
      source = if replacing?, do: "#{name} AS f FINAL", else: "#{name} AS f"

      fields =
        if replacing?,
          do: "f.* EXCEPT (shard_report_id)",
          else: "f.* EXCEPT (shard_report_id) REPLACE (min(f.inserted_at) AS inserted_at)"

      project = if project?, do: "AND f.project_id = r.project_id", else: ""
      grouping = if replacing?, do: "", else: "GROUP BY ALL"

      execute """
      CREATE VIEW reported_#{name} AS
      SELECT * EXCEPT (shard_report_id) FROM #{name} WHERE shard_report_id IS NULL
      UNION ALL
      SELECT #{fields}
      FROM #{source}
      INNER JOIN latest_shard_test_reports AS r
        ON f.test_run_id = r.id AND f.shard_report_id = r.fact_set_id #{project}
      #{grouping}
      """
    end

    for name <- @child_tables do
      execute """
      CREATE VIEW reported_#{name} AS
      SELECT f.* REPLACE (min(f.inserted_at) AS inserted_at)
      FROM #{name} AS f GROUP BY ALL
      """
    end

    summary_columns =
      Enum.map_join(@columns, ",\n", fn {name, type} ->
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

    fields = Enum.map_join(@columns, ", ", fn {name, _} -> to_string(name) end)

    execute """
    CREATE VIEW reported_test_run_summaries AS
    SELECT #{summary_columns}
    FROM latest_shard_test_reports AS r
    GROUP BY project_id, ran_at, id
    """

    execute """
    CREATE VIEW test_run_summaries AS
    SELECT #{fields} FROM test_runs FINAL
    UNION ALL
    SELECT #{fields} FROM reported_test_run_summaries
    """

    execute """
    CREATE VIEW shard_run_summaries AS
    SELECT shard_plan_id, project_id, test_run_id, shard_index, status, duration, ran_at, inserted_at
    FROM shard_runs
    UNION ALL
    SELECT assumeNotNull(shard_plan_id) AS shard_plan_id, project_id, toString(id) AS test_run_id,
      shard_index, status, toUInt64(greatest(duration, 0)) AS duration, execution_started_at AS ran_at, inserted_at
    FROM latest_shard_test_reports
    """
  end

  def down do
    execute "DROP VIEW IF EXISTS shard_run_summaries"
    execute "DROP VIEW IF EXISTS test_run_summaries"
    execute "DROP VIEW IF EXISTS reported_test_run_summaries"
    for name <- @child_tables, do: execute("DROP VIEW IF EXISTS reported_#{name}")

    for {name, _, _} <- @fact_tables do
      execute "DROP VIEW IF EXISTS reported_#{name}"
    end

    execute "DROP VIEW IF EXISTS latest_shard_test_reports"

    for {name, _, _} <- @fact_tables do
      alter table(name), do: remove(:shard_report_id)
    end

    drop table(:shard_test_reports)

    alter table(:test_runs), do: remove(:reporting_version)

    alter table(:shard_plans) do
      remove :assignments
      remove :reporting_version
    end
  end

  defp pin_case_history_projection do
    # Its historical SELECT * has already outgrown its fixed output schema.
    # Pin that output before adding metadata, or ClickHouse treats the new
    # column as a view dependency and refuses to remove it on rollback.
    %{rows: rows} =
      repo().query!("""
      SELECT name FROM system.columns
      WHERE database = currentDatabase() AND table = 'test_case_runs_by_inserted_at'
      ORDER BY position
      """)

    if rows != [] do
      columns = Enum.map_join(rows, ", ", fn [name] -> "`#{name}`" end)

      execute """
      ALTER TABLE test_case_runs_by_inserted_at
      MODIFY QUERY SELECT #{columns} FROM test_case_runs
      """
    end
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
