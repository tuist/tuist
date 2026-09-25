defmodule Tuist.ClickHouse.BackfillTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.ClickHouse.Backfill
  alias Tuist.IngestRepo

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

  describe "lacking/3" do
    test "selects the rows the destination lacks, including ones holding a NULL" do
      # Run against ClickHouse rather than compared as text, because what
      # matters is how the server evaluates a hash over a NULL. The destination
      # holds an empty string where the source has NULL, which must still count
      # as a different row.
      columns = "id UInt8, description Nullable(String)"
      source = "values('#{columns}', (1, 'x'), (2, NULL), (3, NULL))"
      destination = "values('#{columns}', (1, 'x'), (3, ''))"
      where = Backfill.lacking(["id", "description"], destination, {:hash, "1", 0, 1})

      %{rows: rows} = IngestRepo.query!("SELECT id FROM #{source} WHERE #{where} ORDER BY id")

      assert rows == [[2], [3]]
    end
  end

  describe "identity_columns/1" do
    test "leaves out the columns with a default on a plain MergeTree" do
      # Each server fills a defaulted column in for itself when a write omits
      # it, so a row the destination holds could otherwise look missing and be
      # copied a second time.
      shape = %{
        engine: "ReplicatedMergeTree",
        engine_full: "ReplicatedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}') ORDER BY (project_id, name)",
        sorting_key: "project_id, name",
        columns: [{"id", ""}, {"legacy_id", "DEFAULT"}, {"project_id", ""}, {"name", ""}, {"hit_rate", "DEFAULT"}]
      }

      assert Backfill.identity_columns(shape) == ["id", "project_id", "name"]
    end

    test "uses every column when every column has a default" do
      shape = %{
        engine: "MergeTree",
        engine_full: "MergeTree ORDER BY id",
        sorting_key: "id",
        columns: [{"id", "DEFAULT"}, {"name", "DEFAULT"}]
      }

      assert Backfill.identity_columns(shape) == ["id", "name"]
    end

    test "adds a replicated ReplacingMergeTree's version to its sorting key" do
      # Without it, a destination holding an older version of a row counts as
      # holding the row, and the newer version is never copied. The version
      # column has a default here and is kept regardless, since it is what the
      # engine itself compares.
      shape = %{
        engine: "ReplicatedReplacingMergeTree",
        engine_full:
          "ReplicatedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', inserted_at) PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, id)",
        sorting_key: "project_id, id",
        columns: [{"id", ""}, {"project_id", ""}, {"duration", ""}, {"inserted_at", "DEFAULT"}]
      }

      assert Backfill.identity_columns(shape) == ["project_id", "id", "inserted_at"]
    end

    test "adds the sign and version of a VersionedCollapsingMergeTree" do
      shape = %{
        engine: "VersionedCollapsingMergeTree",
        engine_full: "VersionedCollapsingMergeTree(sign, version) ORDER BY id",
        sorting_key: "id",
        columns: [{"id", ""}, {"value", ""}, {"sign", ""}, {"version", ""}]
      }

      assert Backfill.identity_columns(shape) == ["id", "sign", "version"]
    end

    test "identifies a SummingMergeTree by its sorting key alone" do
      # Its arguments are the columns it adds up, which are values rather than
      # anything that tells one row from another.
      shape = %{
        engine: "SummingMergeTree",
        engine_full: "SummingMergeTree(count) ORDER BY (project_id, day)",
        sorting_key: "project_id, day",
        columns: [{"project_id", ""}, {"day", ""}, {"count", ""}]
      }

      assert Backfill.identity_columns(shape) == ["project_id", "day"]
    end
  end

  describe "copy_settings/0" do
    # ClickHouse's own defaults, which are what a copy runs with when these
    # are missing and what cost production three chunks of a wide table.
    @clickhouse_default_insert_block_rows 1_048_576
    @clickhouse_default_insert_block_bytes 268_435_456

    test "caps one statement below the memory the destination server has" do
      settings = Backfill.copy_settings()

      # The replicas run with a 32Gi container limit, of which ClickHouse
      # takes 90% as its server-wide ceiling. A single chunk has to fail on
      # its own well before that, because live shadow writes allocate against
      # the same tracker.
      assert settings[:max_memory_usage] < trunc(0.9 * 32 * 1024 * 1024 * 1024)
    end

    test "reads and writes in smaller blocks than ClickHouse would by default" do
      settings = Backfill.copy_settings()

      assert settings[:max_insert_block_size] < @clickhouse_default_insert_block_rows
      assert settings[:min_insert_block_size_rows] < @clickhouse_default_insert_block_rows
      assert settings[:min_insert_block_size_bytes] < @clickhouse_default_insert_block_bytes
    end

    test "bounds the reading threads, which the container's missing CPU limit does not" do
      assert Backfill.copy_settings()[:max_threads] in 1..8
    end
  end

  describe "run/1" do
    test "refuses to start without a destination" do
      assert {:error, :no_target_configured} = Backfill.run()
    end
  end
end
