defmodule Tuist.Kura.Workers.StaleSelfHostedPeersWorker do
  @moduledoc """
  Periodically drops self-hosted mesh peers that stopped responding.

  Enrollment only ever inserts `kura_self_hosted_peer` endpoints, so a node
  that disappears (a torn-down test instance, a decommissioned box) would
  otherwise stay in the account's mesh forever — every node keeps dialing it
  and queues replication messages for it that can never be delivered, which
  eventually trips the outbox write-shedding threshold. See
  `Tuist.Kura.Mesh.prune_stale_self_hosted_peers/1` for the liveness rule.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Kura.Mesh

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Mesh.prune_stale_self_hosted_peers() do
      [] ->
        :ok

      pruned ->
        urls = Enum.map_join(pruned, ", ", & &1.url)

        Logger.info("[Kura.StaleSelfHostedPeersWorker] pruned #{length(pruned)} stale self-hosted mesh peer(s): #{urls}")
    end

    :ok
  end
end
