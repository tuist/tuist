defmodule Tuist.Kura.Workers.StaleSelfHostedPeersWorker do
  @moduledoc """
  Periodically withholds self-hosted mesh peers that stopped responding.

  Enrollment only ever inserts `kura_self_hosted_peer` endpoints, so a node
  that disappears (a torn-down test instance, a decommissioned box) would
  otherwise stay in the account's mesh forever — every node keeps dialing it
  and queues replication messages for it that can never be delivered, which
  eventually trips the outbox write-shedding threshold. Enrolled nodes prove
  liveness with mesh heartbeats; peers that stop heartbeating are deactivated
  (a returning node reactivates itself by re-enrolling) and purged once their
  peer certificate can no longer be valid. See
  `Tuist.Kura.Mesh.sweep_stale_self_hosted_peers/1` for the liveness rule.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Kura.Mesh

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if __MODULE__.uptime_ms() < Mesh.stale_peer_after_minutes() * 60_000 do
      # After a control-plane outage or deploy, nodes need a heartbeat cycle
      # to refresh their markers before silence is meaningful; sweeping
      # earlier would mass-deactivate live peers and buy each a spurious
      # full re-bootstrap on recovery.
      :ok
    else
      sweep()
    end
  end

  def uptime_ms do
    {uptime_ms, _since_last_call} = :erlang.statistics(:wall_clock)
    uptime_ms
  end

  defp sweep do
    %{deactivated: deactivated, purged: purged} = Mesh.sweep_stale_self_hosted_peers()

    if deactivated != [] do
      urls = Enum.map_join(deactivated, ", ", & &1.url)

      Logger.info(
        "[Kura.StaleSelfHostedPeersWorker] deactivated #{length(deactivated)} stale self-hosted mesh peer(s): #{urls}"
      )
    end

    if purged != [] do
      urls = Enum.map_join(purged, ", ", & &1.url)

      Logger.info(
        "[Kura.StaleSelfHostedPeersWorker] purged #{length(purged)} self-hosted mesh peer(s) deactivated past certificate lifetime: #{urls}"
      )
    end

    :ok
  end
end
