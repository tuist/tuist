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
        try do
          {:ok, _build} = Snapshots.process_build(build)
          :ok
        rescue
          error ->
            if attempt >= max_attempts, do: Snapshots.mark_failed(build)
            reraise error, __STACKTRACE__
        end

      _ ->
        :ok
    end
  end
end
