defmodule Tuist.ClickHouse.BackfillTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouse.Backfill

  describe "month_chunks/3" do
    test "covers the whole range with no gap and no overlap" do
      chunks = Backfill.month_chunks("inserted_at", ~D[2026-01-01], ~D[2026-04-01])

      assert [
               {:month, "inserted_at", ~D[2026-01-01], ~D[2026-02-01]},
               {:month, "inserted_at", ~D[2026-02-01], ~D[2026-03-01]},
               {:month, "inserted_at", ~D[2026-03-01], ~D[2026-04-01]},
               {:month, "inserted_at", ~D[2026-04-01], ~D[2026-05-01]}
             ] = chunks

      # Each chunk begins exactly where the previous ended. A gap silently
      # drops rows no later run looks for, because the ledger records the
      # neighbouring chunks as done; an overlap copies rows twice.
      chunks
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{_, _, _, first_end}, {_, _, second_start, _}] ->
        assert first_end == second_start
      end)
    end

    test "includes the month the range ends in" do
      # `to` is the start of the last month holding data, so that month has to
      # be covered rather than treated as an exclusive bound. Getting this
      # wrong loses the newest month, which is the one anybody looks at first.
      chunks = Backfill.month_chunks("inserted_at", ~D[2026-08-01], ~D[2026-08-01])

      assert [{:month, "inserted_at", ~D[2026-08-01], ~D[2026-09-01]}] = chunks
    end

    test "crosses a year boundary" do
      chunks = Backfill.month_chunks("ran_at", ~D[2025-11-01], ~D[2026-01-01])

      assert [
               {:month, "ran_at", ~D[2025-11-01], ~D[2025-12-01]},
               {:month, "ran_at", ~D[2025-12-01], ~D[2026-01-01]},
               {:month, "ran_at", ~D[2026-01-01], ~D[2026-02-01]}
             ] = chunks
    end

    test "steps over February in a leap year" do
      chunks = Backfill.month_chunks("inserted_at", ~D[2028-01-01], ~D[2028-03-01])

      assert [
               {:month, "inserted_at", ~D[2028-01-01], ~D[2028-02-01]},
               {:month, "inserted_at", ~D[2028-02-01], ~D[2028-03-01]},
               {:month, "inserted_at", ~D[2028-03-01], ~D[2028-04-01]}
             ] = chunks
    end
  end

  describe "predicate/1" do
    test "is half-open, so a row on a boundary belongs to exactly one chunk" do
      predicate = Backfill.predicate({:month, "inserted_at", ~D[2026-03-01], ~D[2026-04-01]})

      assert predicate =~ ">= toDateTime64('2026-03-01 00:00:00', 6)"
      assert predicate =~ "< toDateTime64('2026-04-01 00:00:00', 6)"
      refute predicate =~ "<="
    end

    test "quotes the column, so a column named like a keyword still works" do
      assert Backfill.predicate({:month, "date", ~D[2026-03-01], ~D[2026-04-01]}) =~ "`date` >="
    end

    test "partitions a table with no time column into disjoint hash buckets" do
      # `build_files` is the reason this exists: 257 GiB, unpartitioned, and
      # no column to slice by time.
      predicates = Enum.map(0..3, &Backfill.predicate({:hash, "project_id", &1, 4}))

      assert predicates == [
               "cityHash64(project_id) % 4 = 0",
               "cityHash64(project_id) % 4 = 1",
               "cityHash64(project_id) % 4 = 2",
               "cityHash64(project_id) % 4 = 3"
             ]

      # Every row falls in exactly one bucket, because the modulus covers the
      # whole range of the hash.
      assert length(Enum.uniq(predicates)) == 4
    end
  end

  describe "run/1" do
    test "refuses to start without both endpoints" do
      assert {:error, :no_target_configured} = Backfill.run(source_url: "http://127.0.0.1:1/s", target_url: nil)
      assert {:error, :no_source_configured} = Backfill.run(source_url: nil, target_url: "http://127.0.0.1:1/t")
    end
  end
end
