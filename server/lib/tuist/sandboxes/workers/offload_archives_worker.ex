defmodule Tuist.Sandboxes.Workers.OffloadArchivesWorker do
  @moduledoc """
  Makes room for newer archives by copying the oldest rack archives to account
  storage. Queued on upload pressure and by the periodic archive pass. The store
  lock serializes transfers across the Erlang cluster; publication also checks
  the original row so a retry or concurrent lifecycle change cannot replace it.
  """
  use Oban.Worker,
    queue: :sandbox_archives,
    max_attempts: 5,
    unique: [keys: [:store, :max_bytes], states: [:available, :scheduled, :executing, :retryable], period: :infinity]

  alias Tuist.Sandboxes.Archives

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 31)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"store" => store, "max_bytes" => max_bytes}}) do
    Archives.offload_oldest(store, max_bytes)
  end
end
