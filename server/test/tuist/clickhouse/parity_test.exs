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

  describe "compare/1 in full" do
    setup do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> "http://in-cluster:8123" end)
      :ok
    end

    test "compares a table whose history was not copied only over the span that was" do
      test = self()

      fingerprint = fn sql, opts ->
        send(test, {:fingerprint, sql, opts})
        %{rows: [[1, 1.0, ~N[2026-09-25 05:00:04], ~N[2026-09-25 06:54:51]]]}
      end

      stub_server(Tuist.IngestRepo, 0, fingerprint)
      stub_server(Tuist.ClickHouseRepo, 0, fingerprint)

      assert {:ok, %{compared: 1, matching: ["build_files"], differing: []}} =
               Parity.compare(
                 source_repo: Tuist.IngestRepo,
                 target_repo: Tuist.ClickHouseRepo,
                 tables: ["build_files"],
                 derived: [],
                 as_of: ~U[2026-09-26 06:00:00Z]
               )

      assert_received {:fingerprint, sql, opts}

      # Two weeks back from the comparison. Compared whole, the table would
      # fail on every row older than that, which the destination was never
      # meant to hold.
      assert sql =~ "`inserted_at` >= toDateTime64('2026-09-12 06:00:00', 6)"

      # Still a full comparison's ceiling: the table is not ordered by time,
      # so two weeks of it still reads all of it.
      assert opts |> Keyword.fetch!(:settings) |> Keyword.fetch!(:max_execution_time) == 1800
    end

    # Answers the catalogue queries for a `test_suite_runs`-shaped table:
    # deduplicated, partitioned by the month of `inserted_at`, with its first
    # row at `earliest`. Every fingerprint goes to `on_fingerprint`.
    defp stub_monthly_server(repo, earliest, on_fingerprint) do
      stub(repo, :query!, fn sql, _params, opts ->
        cond do
          sql =~ "SELECT count() AS rows" ->
            on_fingerprint.(sql, opts)

          sql =~ "SELECT name, type FROM system.columns" ->
            %{rows: [["duration", "UInt64"]]}

          sql =~ "SELECT name FROM system.columns" ->
            %{rows: [["inserted_at"]]}

          sql =~ "SELECT engine FROM system.tables" ->
            %{rows: [["ReplacingMergeTree(inserted_at)"]]}

          sql =~ "SELECT engine, partition_key FROM system.tables" ->
            %{rows: [["ReplacingMergeTree(inserted_at)", "toYYYYMM(inserted_at)"]]}

          sql =~ "SELECT min(`inserted_at`)" ->
            %{rows: [[earliest]]}

          true ->
            %{rows: []}
        end
      end)
    end

    defp compare_in_full(table) do
      Parity.compare(
        source_repo: Tuist.IngestRepo,
        target_repo: Tuist.ClickHouseRepo,
        tables: [table],
        derived: [],
        as_of: ~U[2026-09-26 06:00:00Z]
      )
    end

    test "fingerprints a deduplicating table partitioned by month one month at a time" do
      # `test_suite_runs` on production: read with `FINAL` in one go, its 530
      # million rows needed more than the fingerprint's memory ceiling on both
      # servers. `FINAL` never merges across partitions, so a month read on its
      # own holds exactly the rows the whole read would have.
      test = self()

      fingerprint = fn sql, _opts ->
        send(test, {:fingerprint, sql})
        %{rows: [[1, 1, ~N[2026-07-14 10:00:00], ~N[2026-07-14 10:00:00]]]}
      end

      stub_monthly_server(Tuist.IngestRepo, ~N[2026-07-14 10:00:00], fingerprint)

      stub_monthly_server(Tuist.ClickHouseRepo, ~N[2026-07-14 10:00:00], fn _sql, _opts ->
        %{rows: [[1, 1, ~N[2026-07-14 10:00:00], ~N[2026-07-14 10:00:00]]]}
      end)

      compare_in_full("test_suite_runs")

      assert_received {:fingerprint, july}
      assert july =~ "FINAL"
      assert july =~ "`inserted_at` >= toDateTime64('2026-07-14 10:00:00', 6)"
      assert july =~ "`inserted_at` < toDateTime64('2026-08-01 00:00:00', 6)"
      assert_received {:fingerprint, august}
      assert august =~ "`inserted_at` >= toDateTime64('2026-08-01 00:00:00', 6)"
      assert august =~ "`inserted_at` < toDateTime64('2026-09-01 00:00:00', 6)"
      assert_received {:fingerprint, september}
      assert september =~ "`inserted_at` >= toDateTime64('2026-09-01 00:00:00', 6)"
      assert september =~ "`inserted_at` < toDateTime64('2026-09-26 06:00:00', 6)"
      refute_received {:fingerprint, _}
    end

    test "adds the months up into one fingerprint of the table" do
      months = fn september_rows ->
        fn sql, _opts ->
          cond do
            sql =~ ">= toDateTime64('2026-07" -> %{rows: [[2, 10, ~N[2026-07-14 10:00:00], ~N[2026-07-30 08:00:00]]]}
            # A month with no rows reports ClickHouse's zero time as its bounds.
            sql =~ ">= toDateTime64('2026-08" -> %{rows: [[0, 0, ~N[1970-01-01 00:00:00], ~N[1970-01-01 00:00:00]]]}
            true -> %{rows: [[september_rows, 20, ~N[2026-09-02 09:00:00], ~N[2026-09-25 23:00:00]]]}
          end
        end
      end

      stub_monthly_server(Tuist.IngestRepo, ~N[2026-07-14 10:00:00], months.(3))
      stub_monthly_server(Tuist.ClickHouseRepo, ~N[2026-07-14 10:00:00], months.(4))

      assert {:ok, %{differing: [%{table: "test_module_runs", source: source, destination: destination}]}} =
               compare_in_full("test_module_runs")

      assert source == %{
               "rows" => 5,
               "sum_duration" => 30,
               "min_time" => ~N[2026-07-14 10:00:00],
               "max_time" => ~N[2026-09-25 23:00:00]
             }

      assert destination["rows"] == 6
    end
  end

  describe "compare/1 over a window" do
    setup do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> "http://in-cluster:8123" end)
      :ok
    end

    # Answers the catalogue queries for one `build_steps`-shaped table, says
    # its window would read `estimate` rows (or fails to estimate it, given an
    # error), and hands every fingerprint to `on_fingerprint`.
    defp stub_server(repo, estimate, on_fingerprint) do
      stub(repo, :query, fn "EXPLAIN ESTIMATE " <> _statement, _params, _opts ->
        case estimate do
          %Ch.Error{} = error ->
            {:error, error}

          rows ->
            {:ok, %{columns: ["database", "table", "parts", "rows", "marks"], rows: [["default", "t", 10, rows, 1]]}}
        end
      end)

      stub(repo, :query!, fn sql, _params, opts ->
        cond do
          sql =~ "SELECT count() AS rows" ->
            on_fingerprint.(sql, opts)

          sql =~ "SELECT name, type FROM system.columns" ->
            %{rows: [["start_ms", "Float64"]]}

          sql =~ "SELECT name FROM system.columns" ->
            %{rows: [["inserted_at"]]}

          sql =~ "SELECT engine FROM system.tables" ->
            %{rows: [["MergeTree"]]}

          true ->
            %{rows: []}
        end
      end)
    end

    defp compare_window(tables) do
      Parity.compare(
        source_repo: Tuist.IngestRepo,
        target_repo: Tuist.ClickHouseRepo,
        tables: tables,
        derived: [],
        since: ~U[2026-09-25 05:00:00Z],
        as_of: ~U[2026-09-25 06:55:00Z]
      )
    end

    test "skips a table whose window would read too much of it" do
      # `build_files`: nothing about it is organised by `inserted_at`, so a
      # two-hour window read all 26 billion rows on production.
      fail = fn sql, _opts -> flunk("fingerprinted a table it cannot bound: #{sql}") end
      stub_server(Tuist.IngestRepo, 26_110_422_531, fail)
      stub_server(Tuist.ClickHouseRepo, 26_110_422_531, fail)

      assert {:ok, %{compared: 0, skipped: ["build_files"], differing: []}} = compare_window(["build_files"])
    end

    test "compares a table the source cannot estimate, so its failure is reported" do
      # A table only the destination has: the estimate fails on the source, and
      # the comparison reports the table rather than failing as a whole.
      missing = %Ch.Error{code: 60, message: "Unknown table"}
      stub_server(Tuist.IngestRepo, missing, fn _sql, _opts -> raise missing end)

      stub_server(Tuist.ClickHouseRepo, 0, fn _sql, _opts ->
        %{rows: [[1, 1.0, ~N[2026-09-25 05:00:04], ~N[2026-09-25 06:54:51]]]}
      end)

      assert {:ok, %{compared: 1, differing: [%{table: "kura_new_events", source: %{error: _}}]}} =
               compare_window(["kura_new_events"])
    end

    test "compares a table whose estimate comes back in a shape it cannot read" do
      # An answer this does not recognise is an absent estimate, and absent
      # estimates are compared. Reading the count by position instead would
      # fail inside the enumeration, where nothing rescues it, so one
      # unreadable answer would end the whole comparison.
      fingerprint = fn _sql, _opts ->
        %{rows: [[1, 1.0, ~N[2026-09-25 05:00:04], ~N[2026-09-25 06:54:51]]]}
      end

      stub_server(Tuist.IngestRepo, 0, fingerprint)
      stub_server(Tuist.ClickHouseRepo, 0, fingerprint)

      stub(Tuist.IngestRepo, :query, fn "EXPLAIN ESTIMATE " <> _statement, _params, _opts ->
        {:ok, %{columns: ["database", "table", "parts", "estimated_rows", "marks"], rows: [["default", "t", 10, 1, 1]]}}
      end)

      assert {:ok, %{compared: 1, matching: ["build_steps"], skipped: []}} = compare_window(["build_steps"])
    end

    test "bounds each fingerprint on the server and does not retry it" do
      test = self()

      fingerprint = fn values ->
        fn _sql, opts ->
          send(test, {:fingerprint, opts})
          %{rows: [values]}
        end
      end

      # The two sums of the same rows that production reported as a
      # difference, because they disagree in the fourth decimal.
      stub_server(
        Tuist.IngestRepo,
        35_007_490,
        fingerprint.([10, 2_025_942_667_017.596, ~N[2026-09-25 05:00:04], ~N[2026-09-25 06:54:51]])
      )

      stub_server(
        Tuist.ClickHouseRepo,
        35_007_490,
        fingerprint.([10, 2_025_942_667_017.5947, ~N[2026-09-25 05:00:04], ~N[2026-09-25 06:54:51]])
      )

      assert {:ok, %{compared: 1, matching: ["build_steps"], differing: []}} = compare_window(["build_steps"])

      assert_received {:fingerprint, opts}
      assert opts[:checkout_retries] == 0
      max_execution_time = opts |> Keyword.fetch!(:settings) |> Keyword.fetch!(:max_execution_time)
      assert opts[:timeout] > to_timeout(second: max_execution_time)
    end
  end

  describe "same_fingerprint?/2" do
    test "treats float sums that differ in their last bits as equal" do
      assert Parity.same_fingerprint?(
               %{"rows" => 10, "sum_start_ms" => 2_025_942_667_017.596},
               %{"rows" => 10, "sum_start_ms" => 2_025_942_667_017.5947}
             )
    end

    test "tells float sums apart once they differ by more than rounding" do
      refute Parity.same_fingerprint?(%{"sum_start_ms" => 2_025_942_667_017.596}, %{
               "sum_start_ms" => 2_025_942_667_117.596
             })
    end

    test "compares integers, times and missing columns exactly" do
      refute Parity.same_fingerprint?(%{"rows" => 10}, %{"rows" => 11})
      refute Parity.same_fingerprint?(%{"min_time" => ~N[2026-09-25 05:00:04]}, %{"min_time" => ~N[2026-09-25 05:00:05]})
      refute Parity.same_fingerprint?(%{"rows" => 10, "sum_a" => 1}, %{"rows" => 10, "sum_b" => 1})
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
