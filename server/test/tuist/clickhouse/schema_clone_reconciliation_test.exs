defmodule Tuist.ClickHouse.SchemaCloneReconciliationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.ClickHouse.Endpoints
  alias Tuist.ClickHouse.SchemaClone
  alias Tuist.IngestRepo

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)
    suffix = System.unique_integer([:positive])
    source = "schema_clone_source_#{suffix}"
    target = "schema_clone_target_#{suffix}"

    on_exit(fn ->
      IngestRepo.query!("DROP DATABASE IF EXISTS #{target}")
      IngestRepo.query!("DROP DATABASE IF EXISTS #{source}")
      Sandbox.stop_owner(owner)
    end)

    IngestRepo.query!("CREATE DATABASE #{source}")
    IngestRepo.query!("CREATE DATABASE #{target}")

    IngestRepo.query!("""
    CREATE TABLE #{source}.test_runs (id UInt64, reporting_version UInt8 DEFAULT 0)
    ENGINE = ReplacingMergeTree ORDER BY id
    """)

    IngestRepo.query!("""
    CREATE TABLE #{source}.test_case_runs (id UInt64, shard_report_id Nullable(UInt64))
    ENGINE = MergeTree ORDER BY id
    """)

    IngestRepo.query!("""
    CREATE TABLE #{source}.shard_test_reports (fact_set_id UInt64)
    ENGINE = MergeTree ORDER BY fact_set_id
    """)

    IngestRepo.query!("""
    CREATE VIEW #{source}.latest_shard_test_reports AS
    SELECT fact_set_id FROM #{source}.shard_test_reports
    """)

    IngestRepo.query!("""
    CREATE VIEW #{source}.reported_test_case_runs AS
    SELECT c.id, c.shard_report_id FROM #{source}.test_case_runs AS c
    LEFT JOIN #{source}.latest_shard_test_reports AS r ON c.shard_report_id = r.fact_set_id
    """)

    IngestRepo.query!("""
    CREATE VIEW #{source}.test_run_summaries AS
    SELECT id, reporting_version FROM #{source}.test_runs FINAL
    """)

    stub(Endpoints, :with_repos, fn _opts, fun ->
      fun.(%{repo: IngestRepo, database: source}, %{repo: IngestRepo, database: target})
    end)

    %{source: source, target: target}
  end

  test "one reconciliation adds columns before creating dependent views", %{target: target} do
    IngestRepo.query!("CREATE TABLE #{target}.test_runs (id UInt64) ENGINE = ReplacingMergeTree ORDER BY id")
    IngestRepo.query!("CREATE TABLE #{target}.test_case_runs (id UInt64) ENGINE = MergeTree ORDER BY id")
    IngestRepo.query!("INSERT INTO #{target}.test_runs VALUES (7)")
    IngestRepo.query!("INSERT INTO #{target}.test_case_runs VALUES (9)")

    stub(IngestRepo, :query!, fn statement, params, opts ->
      result = Mimic.call_original(IngestRepo, :query!, [statement, params, opts])

      if String.starts_with?(statement, ["ALTER TABLE ", "CREATE "]) do
        send(self(), {:schema_ddl, statement})
      end

      result
    end)

    assert {:ok, report} = SchemaClone.reconcile()

    statements =
      for _ <- 1..(length(report.columns_added) + length(report.created)) do
        assert_receive {:schema_ddl, statement}
        statement
      end

    assert Enum.all?(Enum.take(statements, 2), &String.starts_with?(&1, "ALTER TABLE "))
    assert Enum.sort(report.columns_added) == ["test_case_runs.shard_report_id", "test_runs.reporting_version"]

    assert report.created == [
             "shard_test_reports",
             "latest_shard_test_reports",
             "reported_test_case_runs",
             "test_run_summaries"
           ]

    assert %{rows: [[7, 0]]} = IngestRepo.query!("SELECT id, reporting_version FROM #{target}.test_run_summaries")
    assert %{rows: [[9, nil]]} = IngestRepo.query!("SELECT id, shard_report_id FROM #{target}.reported_test_case_runs")
    assert {:ok, %{created: [], columns_added: []}} = SchemaClone.reconcile()
  end

  test "an empty destination still creates tables before dependent views", %{target: target} do
    assert {:ok, report} = SchemaClone.reconcile()
    assert report.columns_added == []
    assert length(report.created) == 6
    refute Enum.any?(report.created, &String.contains?(&1, "failed"))
    assert %{rows: [[0]]} = IngestRepo.query!("SELECT count() FROM #{target}.test_run_summaries")
    assert %{rows: [[0]]} = IngestRepo.query!("SELECT count() FROM #{target}.reported_test_case_runs")
    assert {:ok, %{created: [], columns_added: []}} = SchemaClone.reconcile()
  end
end
