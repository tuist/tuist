defmodule Tuist.IngestRepo.ShadowWriteTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.IngestRepo.ShadowWrite

  describe "write?/1" do
    test "mirrors the buffer flush, which is how most rows arrive" do
      # `Tuist.Ingestion.Buffer` flushes RowBinary through
      # `IngestRepo.query/3`. If this were not recognised, the mirror would
      # miss nearly every row in the system while looking healthy.
      assert ShadowWrite.write?("INSERT INTO command_events (id, name) FORMAT RowBinary")
    end

    test "mirrors the mutation-based deletes" do
      # These erase a deleted project's or bundle's rows. Not mirroring them
      # leaves the destination holding data the source has erased, which is a
      # parity failure that grows rather than a missing row.
      assert ShadowWrite.write?(
               "ALTER TABLE command_events DELETE WHERE project_id IN ({project_ids:Array(Int64)}) SETTINGS mutations_sync = 0"
             )

      assert ShadowWrite.write?("ALTER TABLE bundles DELETE WHERE id = {bundle_id:UUID} SETTINGS mutations_sync = 1")
    end

    test "mirrors an INSERT ... SELECT" do
      # The flaky-test correction path writes this way.
      assert ShadowWrite.write?("INSERT INTO test_case_runs (id, project_id)\nSELECT id, project_id FROM test_case_runs")
    end

    test "does not mirror the metadata introspection read" do
      # `Tuist.CommandEvents` deliberately routes this through the write repo
      # to bypass the sandboxed read repo. Mirroring it would double the cost
      # of every metadata query for no benefit.
      refute ShadowWrite.write?("SELECT name FROM system.columns WHERE table = {table:String}")
      refute ShadowWrite.write?("SELECT count() FROM command_events")
    end

    test "is insensitive to case and leading whitespace, which heredocs add" do
      assert ShadowWrite.write?("\n    insert into command_events FORMAT RowBinary")
      assert ShadowWrite.write?("  Alter Table bundles DELETE WHERE id = 1")
      refute ShadowWrite.write?("\n  select 1")
    end

    test "does not mirror statements it does not recognise" do
      # The safe direction: an unrecognised statement produces a missing row
      # that the parity report catches, rather than a mirrored read.
      refute ShadowWrite.write?("OPTIMIZE TABLE command_events FINAL")
      refute ShadowWrite.write?("CREATE TABLE t (id UUID) ENGINE = MergeTree ORDER BY id")
      refute ShadowWrite.write?("SYSTEM FLUSH LOGS")
      refute ShadowWrite.write?(nil)
      refute ShadowWrite.write?(:not_a_statement)
    end
  end

  describe "mirroring while no destination is configured" do
    test "is inert, so every environment but a migrating one is unaffected" do
      # `TUIST_CLICKHOUSE_BARE_METAL_URL` is unset in test, so these must all
      # be no-ops rather than attempts to reach an unstarted repository.
      assert :ok = ShadowWrite.mirror_statement("INSERT INTO command_events FORMAT RowBinary", [], [])
      assert :ok = ShadowWrite.mirror_insert_all("command_events", [], [])
      assert :ok = ShadowWrite.mirror_insert(%{}, [])
    end
  end

  describe "mirroring a raw write" do
    setup do
      stub(Tuist.Environment, :clickhouse_shadow_writes_enabled?, fn -> true end)
      :ok
    end

    test "does not let a missing task supervisor reach the caller" do
      # The supervisor is absent under `bin/tuist eval`, where a migration's
      # own INSERT takes this path, and during shutdown before the ingest
      # buffers make their final flush. Starting a child is a call into it, so
      # its absence is an exit, and an exit here would surface in a request
      # whose primary write already succeeded.
      refute Process.whereis(Tuist.IngestRepo.ShadowWrite.TaskSupervisor)

      expect(Tuist.ShadowIngestRepo, :query, fn _sql, _params, _opts -> {:ok, %{rows: []}} end)

      assert :ok = ShadowWrite.mirror_statement("INSERT INTO t VALUES (1)", [], [])
    end

    test "treats a returned error tuple as a failure rather than a success" do
      # `query/3` answers `{:error, exception}` instead of raising, so an
      # unmatched result would count a rejected write as mirrored and never
      # retry it, which is the silent loss the counter exists to surface.
      test_process = self()

      stub(Tuist.ShadowIngestRepo, :query, fn _sql, _params, _opts ->
        send(test_process, :attempted)
        {:error, %Ch.Error{code: 60, message: "UNKNOWN_TABLE"}}
      end)

      ShadowWrite.mirror_statement("ALTER TABLE t DELETE WHERE 1", [], [])

      # Retried rather than accepted: three attempts, not one.
      assert_received :attempted
      assert_received :attempted
      assert_received :attempted
    end
  end
end
