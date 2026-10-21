defmodule Tuist.Shards.ImmutableReportPreflightTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.IngestRepo

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "the rollout preflight analyzes every required view against the migrated schema" do
    for statement <- statements() do
      assert String.starts_with?(statement, ["SELECT ", "EXPLAIN PLAN "])
      assert %{rows: [_ | _]} = IngestRepo.query!(statement)
    end
  end

  test "the inventory check rejects a destination without the required views" do
    database = "missing_shard_preflight_#{System.unique_integer([:positive])}"

    statement =
      statements()
      |> Enum.find(&String.starts_with?(&1, "SELECT throwIf"))
      |> String.replace("currentDatabase()", "'#{database}'")

    assert_raise Ch.Error, ~r/Missing immutable shard reporting views/, fn -> IngestRepo.query!(statement) end
  end

  test "query analysis rejects a typed view whose source column is missing" do
    database = "shard_preflight_#{System.unique_integer([:positive])}"
    on_exit(fn -> IngestRepo.query!("DROP DATABASE IF EXISTS #{database}") end)
    IngestRepo.query!("CREATE DATABASE #{database}")

    IngestRepo.query!("""
    CREATE TABLE #{database}.test_runs (id UUID)
    ENGINE = ReplacingMergeTree ORDER BY id
    """)

    IngestRepo.query!("""
    CREATE VIEW #{database}.test_run_summaries (id UUID, reporting_version UInt8) AS
    SELECT id, reporting_version FROM #{database}.test_runs FINAL
    """)

    statement =
      statements()
      |> Enum.find(&String.contains?(&1, "FROM test_run_summaries LIMIT"))
      |> String.replace("FROM test_run_summaries", "FROM #{database}.test_run_summaries")

    assert_raise Ch.Error, ~r/reporting_version/, fn -> IngestRepo.query!(statement) end
  end

  defp statements do
    "../../../docs/immutable-shard-report-preflight.sql"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> then(&Regex.replace(~r/^--.*$/m, &1, ""))
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
