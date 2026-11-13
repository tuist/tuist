defmodule Tuist.Sandboxes.Workers.ReleaseRemovedNodesWorker do
  @moduledoc """
  Releases the sandboxes of nodes that left the cluster, so their sessions
  start afresh instead of waiting on a node that will never come back. See
  `Tuist.Sandboxes.release_removed_nodes/0`.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 50]

  alias Tuist.Sandboxes

  @impl Oban.Worker
  def perform(_job) do
    Sandboxes.release_removed_nodes()
    :ok
  end
end
