defmodule Tuist.IngestRepo.ShadowWrite.Drainer do
  @moduledoc """
  Holds back the shutdown of the mirror's task supervisor until the mirrored
  inserts in it have finished.

  A mirrored insert runs as a task under `Tuist.IngestRepo.ShadowWrite`'s task
  supervisor, and a supervisor stopping its children ends a task at once: a
  task does not trap exits, so the `:shutdown` signal kills it rather than
  waiting out the child's shutdown timeout. Every mirror in flight when a pod
  stopped was lost that way, along with the ingest buffers' final flushes,
  which hand their mirrors to the same supervisor on their way down.

  The application starts this after the task supervisor and before the
  buffers, and stops children in reverse, so it is stopped after every buffer
  has flushed and before the task supervisor is, and drains in between.
  """
  use GenServer

  alias Tuist.IngestRepo.ShadowWrite

  # Bounded, so a mirror wedged on a destination that has stopped answering
  # cannot hold the pod past its grace period. A healthy mirror takes
  # milliseconds.
  @drain_timeout_ms 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # Longer than the drain, or its own supervisor kills it mid-drain.
      shutdown: @drain_timeout_ms + 5_000
    }
  end

  @impl true
  def init(_opts) do
    # Without this the shutdown signal ends this process before `terminate/2`
    # runs, which is the same fault it exists to fix.
    Process.flag(:trap_exit, true)
    {:ok, nil}
  end

  @impl true
  def terminate(_reason, _state) do
    ShadowWrite.drain(@drain_timeout_ms)
  end
end
