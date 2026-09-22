defmodule Tuist.ClickHouse.ParityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouse.Parity

  describe "compare/1" do
    setup do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> "http://in-cluster:8123" end)
      :ok
    end

    defp stub_ledger(repo, versions) do
      stub(repo, :query!, fn sql, _params, _opts ->
        if sql =~ "schema_migrations", do: %{rows: Enum.map(versions, &[&1])}, else: %{rows: []}
      end)
    end

    defp compare do
      Parity.compare(source_repo: Tuist.IngestRepo, target_repo: Tuist.ClickHouseRepo, tables: [], derived: [])
    end

    test "reports the ledger versions missing on the destination and the ones only it has" do
      stub_ledger(Tuist.IngestRepo, [20_260_901_000_000, 20_260_910_150_000, 20_260_911_140_000])
      stub_ledger(Tuist.ClickHouseRepo, [20_260_901_000_000, 20_260_911_140_000, 20_260_912_090_000])

      assert {:ok, %{migrations: migrations}} = compare()

      assert migrations == %{missing_on_destination: [20_260_910_150_000], only_on_destination: [20_260_912_090_000]}
    end

    test "reports no ledger drift when both servers hold the same versions" do
      stub_ledger(Tuist.IngestRepo, [20_260_901_000_000, 20_260_910_150_000])
      stub_ledger(Tuist.ClickHouseRepo, [20_260_910_150_000, 20_260_901_000_000])

      assert {:ok, %{migrations: %{missing_on_destination: [], only_on_destination: []}}} = compare()
    end
  end

  describe "ttl_expression/1" do
    test "reads the expression a table's TTL deletes rows by" do
      engine_full =
        "MergeTree PARTITION BY toYYYYMMDD(inserted_at) ORDER BY (inserted_at, id) TTL inserted_at + toIntervalDay(30) SETTINGS index_granularity = 8192"

      assert Parity.ttl_expression(engine_full) == "inserted_at + toIntervalDay(30)"
    end

    test "reads it from a replicated engine and drops an explicit DELETE" do
      engine_full =
        "ReplicatedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}') PARTITION BY toYYYYMMDD(inserted_at) ORDER BY (inserted_at, id) TTL inserted_at + toIntervalDay(30) DELETE SETTINGS index_granularity = 8192"

      assert Parity.ttl_expression(engine_full) == "inserted_at + toIntervalDay(30)"
    end

    test "is nil for a table without a TTL" do
      assert Parity.ttl_expression("MergeTree ORDER BY id SETTINGS index_granularity = 8192") == nil
    end

    test "is nil for a TTL that moves data or has more than one rule" do
      # Neither is a single expression rows are deleted by, so a table with one
      # is compared as before rather than over a guessed window.
      assert Parity.ttl_expression(
               "MergeTree ORDER BY id TTL d + toIntervalDay(7) TO VOLUME 'cold' SETTINGS index_granularity = 8192"
             ) ==
               nil

      assert Parity.ttl_expression("MergeTree ORDER BY id TTL d + toIntervalDay(7), d + toIntervalDay(30) DELETE") == nil
    end
  end
end
