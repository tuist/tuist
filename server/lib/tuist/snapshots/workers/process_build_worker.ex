defmodule Tuist.Snapshots.Workers.ProcessBuildWorker do
  @moduledoc """
  Compares a completed snapshot build with its baseline. Comparing again
  rewrites the same rows, so a retried job is harmless; the last failed
  attempt marks the build as failed.

  Runs on the `:process_snapshots` queue, which the processor pods consume
  when they run (web pods then delegate it): decoding and diffing
  full-resolution images takes a few hundred megabytes per job. Everything it
  reads and writes in PostgreSQL must be granted to the processor role
  (`Tuist.Release`'s processor tables).

  While it runs, the job touches its build's `updated_at` every
  `heartbeat_interval/0`. A job whose pod died (a deploy, an eviction) stops
  beating, and `Tuist.Snapshots.Workers.RecoverStalledBuildsWorker` requeues
  it within minutes instead of leaving the CLI waiting on Oban's 30-minute
  Lifeline.
  """
  use Oban.Worker,
    queue: :process_snapshots,
    max_attempts: 3,
    unique: [keys: [:build_id], states: [:available, :scheduled, :executing]]

  alias Tuist.Repo
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Build

  def heartbeat_interval, do: to_timeout(second: 30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id}, attempt: attempt, max_attempts: max_attempts}) do
    case Repo.get(Build, build_id) do
      %Build{state: "processing"} = build ->
        # Images are compared in linked tasks: a task that crashes or times
        # out would kill this process past any rescue. Trapping exits turns
        # it into an exit we catch, so the last attempt still fails the build.
        trap_exit = Process.flag(:trap_exit, true)
        heartbeat = start_heartbeat(build)

        try do
          {:ok, _build} = Snapshots.process_build(build)
          :ok
        catch
          kind, reason ->
            if attempt >= max_attempts, do: Snapshots.mark_failed(build)
            :erlang.raise(kind, reason, __STACKTRACE__)
        after
          send(heartbeat, :stop)
          Process.flag(:trap_exit, trap_exit)
        end

      _ ->
        :ok
    end
  end

  # Unlinked, so a failed beat never fails the comparison, and monitoring the
  # job's process, so the beats stop with it however it ends.
  defp start_heartbeat(build) do
    parent = self()

    {:ok, pid} =
      Task.start(fn ->
        ref = Process.monitor(parent)
        beat(build, ref)
      end)

    pid
  end

  defp beat(build, ref) do
    Snapshots.touch_processing(build)

    receive do
      :stop -> :ok
      {:DOWN, ^ref, :process, _, _} -> :ok
    after
      heartbeat_interval() -> beat(build, ref)
    end
  end
end
