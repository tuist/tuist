defmodule Tuist.Shards.ImmutableReportConcurrencyTest do
  # Independent connections commit outside the sandbox and affect global counts.
  # Keep concurrent writers within each test, but isolate them from other modules.
  use ExUnit.Case, async: false

  alias Tuist.IngestRepo

  setup do
    opts = Keyword.take(IngestRepo.config(), [:hostname, :port, :database, :username, :password])
    {:ok, reader} = Ch.start_link(opts)
    project_id = -System.unique_integer([:positive, :monotonic])
    id = Ecto.UUID.generate()

    on_exit(fn ->
      {:ok, cleanup} = Ch.start_link(opts)

      Ch.query!(
        cleanup,
        "ALTER TABLE shard_test_reports DELETE WHERE project_id = {project:Int64} SETTINGS mutations_sync = 1",
        %{project: project_id}
      )

      GenServer.stop(cleanup)
    end)

    %{opts: opts, reader: reader, project_id: project_id, id: id}
  end

  test "independent simultaneous first and final writers converge without a merge", context do
    writers = for index <- 0..1, do: writer(context, index)
    Enum.each(writers, fn task -> assert_receive {:ready, pid} when pid == task.pid end)
    Enum.each(writers, &send(&1.pid, :write))
    Enum.each(writers, &Task.await(&1, 15_000))

    assert [[context.id, "success", 200]] == summary(context)

    assert %{rows: [[0]]} =
             Ch.query!(context.reader, "SELECT count() FROM test_runs WHERE project_id = {project:Int64}", %{
               project: context.project_id
             })
  end

  test "late reports repair a timed-out aggregate without a reaper rewrite", context do
    write(context.reader, context, 0, "success", 0, 0, 2, "2000-01-01 00:00:00.000000")
    assert [[context.id, "failure", 100]] == summary(context)
    write(context.reader, context, 1, "success", 0, 0, 2, "2000-01-01 00:00:00.000000")
    assert [[context.id, "success", 200]] == summary(context)
  end

  test "producer ordering beats replica clocks and replay order", context do
    write(context.reader, context, 0, "success", 2, 1, 2, "2000-01-01 00:00:00.000000")
    write(context.reader, context, 1, "success", 0, 0, 2, "2000-01-01 00:00:00.000000")
    write(context.reader, context, 0, "failure", 1, 99, 2, "2099-01-01 00:00:00.000000")
    write(context.reader, context, 0, "processing", 2, 99, 0, "2099-01-01 00:00:00.000000")
    assert [[context.id, "success", 200]] == summary(context)
  end

  test "replaying the same observations on independent connections leaves one run", context do
    writers = for index <- [0, 1, 0, 1], do: writer(context, index)
    Enum.each(writers, fn task -> assert_receive {:ready, pid} when pid == task.pid end)
    Enum.each(writers, &send(&1.pid, :write))
    Enum.each(writers, &Task.await(&1, 15_000))
    assert [[context.id, "success", 200]] == summary(context)
  end

  test "a one-shard processing run also expires without a persisted update", context do
    write(context.reader, Map.put(context, :shard_count, 1), 0, "processing", 0, 0, 0, "2000-01-01 00:00:00.000000")
    assert [[context.id, "failure", 100]] == summary(context)
  end

  defp writer(context, index) do
    parent = self()

    Task.async(fn ->
      {:ok, connection} = Ch.start_link(context.opts)
      send(parent, {:ready, self()})

      receive do
        :write -> write(connection, context, index, "success", 0, 0, 2, "2000-01-01 00:00:00.000000")
      after
        10_000 -> raise "writer was not released"
      end

      GenServer.stop(connection)
    end)
  end

  defp write(connection, context, index, status, attempt, revision, phase, inserted_at) do
    Ch.query!(
      connection,
      """
      INSERT INTO shard_test_reports
        (id, shard_plan_id, project_id, ran_at, inserted_at, execution_started_at,
         reporting_version, shard_index, shard_count, status, duration,
         shard_attempt, shard_report_revision, report_phase, report_digest)
      VALUES ({id:UUID}, {id:UUID}, {project:Int64}, '2026-10-17 00:00:00', {inserted:DateTime64(6)},
        '2026-10-17 00:00:00', 1, {index:UInt16}, {count:UInt16}, {status:String}, {duration:Int32},
        {attempt:UInt32}, {revision:UInt32}, {phase:UInt8}, {status:String})
      """,
      %{
        id: context.id,
        project: context.project_id,
        index: index,
        status: status,
        duration: 100 * (index + 1),
        attempt: attempt,
        revision: revision,
        phase: phase,
        inserted: inserted_at,
        count: Map.get(context, :shard_count, 2)
      }
    )
  end

  defp summary(context) do
    %{rows: rows} =
      Ch.query!(
        context.reader,
        "SELECT toString(id), status, duration FROM test_run_summaries WHERE project_id = {project:Int64}",
        %{project: context.project_id}
      )

    rows
  end
end
