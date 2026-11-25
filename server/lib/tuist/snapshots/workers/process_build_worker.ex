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
  """
  use Oban.Worker,
    queue: :process_snapshots,
    max_attempts: 3,
    unique: [keys: [:build_id], states: [:available, :scheduled, :executing]]

  alias Tuist.Repo
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Build

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id}, attempt: attempt, max_attempts: max_attempts}) do
    case Repo.get(Build, build_id) do
      %Build{state: "processing"} = build ->
        # Images are compared in linked tasks: a task that crashes or times
        # out would kill this process past any rescue. Trapping exits turns
        # it into an exit we catch, so the last attempt still fails the build.
        trap_exit = Process.flag(:trap_exit, true)

        try do
          {:ok, _build} = Snapshots.process_build(build)
          :ok
        catch
          kind, reason ->
            if attempt >= max_attempts, do: Snapshots.mark_failed(build)
            :erlang.raise(kind, reason, __STACKTRACE__)
        after
          Process.flag(:trap_exit, trap_exit)
        end

      _ ->
        :ok
    end
  end
end
