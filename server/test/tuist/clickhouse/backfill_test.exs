defmodule Tuist.ClickHouse.BackfillTest do
  use ExUnit.Case, async: true

  alias Tuist.ClickHouse.Backfill

  @cutoff ~U[2026-09-04 07:30:00Z]

  describe "month_chunks/4" do
    test "covers the whole range with no gap and no overlap" do
      chunks = Backfill.month_chunks("inserted_at", ~D[2026-01-01], ~D[2026-04-01], @cutoff)

      assert [
               {:range, "inserted_at", ~U[2026-01-01 00:00:00Z], ~U[2026-02-01 00:00:00Z]},
               {:range, "inserted_at", ~U[2026-02-01 00:00:00Z], ~U[2026-03-01 00:00:00Z]},
               {:range, "inserted_at", ~U[2026-03-01 00:00:00Z], ~U[2026-04-01 00:00:00Z]},
               {:range, "inserted_at", ~U[2026-04-01 00:00:00Z], ~U[2026-05-01 00:00:00Z]}
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

    test "stops at the cutoff rather than at the end of its month" do
      # The cutover cannot wait for a month boundary, so the month holding the
      # cutoff is copied as a partial interval. Rounding it up to the month end
      # would copy rows the dual write had already delivered.
      chunks = Backfill.month_chunks("inserted_at", ~D[2026-08-01], ~D[2026-09-01], @cutoff)

      assert [
               {:range, "inserted_at", ~U[2026-08-01 00:00:00Z], ~U[2026-09-01 00:00:00Z]},
               {:range, "inserted_at", ~U[2026-09-01 00:00:00Z], @cutoff}
             ] = chunks
    end

    test "drops the months that begin at or after the cutoff" do
      # Those rows belong to the dual write. Copying them as well is what the
      # cutoff exists to prevent.
      assert Backfill.month_chunks("inserted_at", ~D[2026-09-01], ~D[2026-11-01], @cutoff) == [
               {:range, "inserted_at", ~U[2026-09-01 00:00:00Z], @cutoff}
             ]

      assert Backfill.month_chunks("inserted_at", ~D[2026-10-01], ~D[2026-11-01], @cutoff) == []
    end

    test "crosses a year boundary" do
      chunks = Backfill.month_chunks("ran_at", ~D[2025-11-01], ~D[2026-01-01], @cutoff)

      assert [
               {:range, "ran_at", ~U[2025-11-01 00:00:00Z], ~U[2025-12-01 00:00:00Z]},
               {:range, "ran_at", ~U[2025-12-01 00:00:00Z], ~U[2026-01-01 00:00:00Z]},
               {:range, "ran_at", ~U[2026-01-01 00:00:00Z], ~U[2026-02-01 00:00:00Z]}
             ] = chunks
    end

    test "steps over February in a leap year" do
      chunks = Backfill.month_chunks("inserted_at", ~D[2028-01-01], ~D[2028-03-01], ~U[2028-12-01 00:00:00Z])

      assert [
               {:range, "inserted_at", ~U[2028-01-01 00:00:00Z], ~U[2028-02-01 00:00:00Z]},
               {:range, "inserted_at", ~U[2028-02-01 00:00:00Z], ~U[2028-03-01 00:00:00Z]},
               {:range, "inserted_at", ~U[2028-03-01 00:00:00Z], ~U[2028-04-01 00:00:00Z]}
             ] = chunks
    end
  end

  describe "predicate/1" do
    test "is half-open, so a row on a boundary belongs to exactly one chunk" do
      predicate = Backfill.predicate({:range, "inserted_at", ~U[2026-03-01 00:00:00Z], ~U[2026-04-01 00:00:00Z]})

      assert predicate =~ ">= toDateTime64('2026-03-01 00:00:00', 6)"
      assert predicate =~ "< toDateTime64('2026-04-01 00:00:00', 6)"
      refute predicate =~ "<="
    end

    test "carries the cutoff's time of day, not just its date" do
      predicate = Backfill.predicate({:range, "inserted_at", ~U[2026-09-01 00:00:00Z], @cutoff})

      assert predicate =~ "< toDateTime64('2026-09-04 07:30:00', 6)"
    end

    test "quotes the column, so a column named like a keyword still works" do
      assert Backfill.predicate({:range, "date", ~U[2026-03-01 00:00:00Z], ~U[2026-04-01 00:00:00Z]}) =~ "`date` >="
    end

    test "partitions a table with no time column into disjoint hash buckets" do
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
    test "refuses to start without a destination" do
      assert {:error, :no_target_configured} = Backfill.run()
    end
  end
end
