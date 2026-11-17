defmodule Tuist.Agents.PromExPlugin do
  @moduledoc """
  Gauges for durable agent sessions (`Tuist.Agents`).

  Sessions that want a host but that no pod holds are read from the shared
  `agent_sessions` table, so every node reports them, including when no
  agents pod is left to host them. They are the backlog the agents pods'
  memory autoscaler cannot see: a pod past its memory threshold stops
  claiming, so sessions wait once the autoscaler is at its maximum or the
  cluster has no room for another pod. Age, not count, tells a backlog that
  drains from one that does not. Sessions delayed after a failure
  (`Tuist.Agents.Lease.release/3`) are not waiting until their delay passes.

  Each node also reports how many sessions it hosts.
  """
  use PromEx.Plugin

  import Ecto.Query, only: [from: 2]

  alias Tuist.Agents.Runner
  alias Tuist.Repo

  @waiting_event [:prom_ex, :plugin, :tuist, :agents, :sessions, :waiting]
  @hosted_event [:prom_ex, :plugin, :tuist, :agents, :node, :hosted]

  @impl true
  def polling_metrics(_opts) do
    [
      Polling.build(
        :tuist_agents_session_poll_metrics,
        10_000,
        {__MODULE__, :execute_session_metrics, []},
        [
          last_value([:tuist, :agents, :sessions, :waiting, :count],
            event_name: @waiting_event,
            description: "Agent sessions that want a host and that no pod holds.",
            measurement: :count
          ),
          last_value([:tuist, :agents, :sessions, :oldest, :waiting, :age, :seconds],
            event_name: @waiting_event,
            description: "Seconds the longest-waiting agent session has wanted a host (0 when none waits).",
            measurement: :age_seconds
          ),
          last_value([:tuist, :agents, :node, :hosted, :sessions, :count],
            event_name: @hosted_event,
            description: "Agent sessions this node hosts.",
            measurement: :count
          )
        ]
      )
    ]
  end

  def execute_session_metrics do
    {count, age} =
      Repo.one(
        from(s in "agent_sessions",
          where:
            s.wanted and s.wanted_at <= fragment("CURRENT_TIMESTAMP") and is_nil(s.deleted_at) and
              (is_nil(s.lease_expires_at) or s.lease_expires_at < fragment("CURRENT_TIMESTAMP")),
          select:
            {count(s.id), fragment("COALESCE(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - min(?)), 0)::float", s.wanted_at)}
        ),
        log: false
      )

    :telemetry.execute(@waiting_event, %{count: count, age_seconds: age}, %{})

    if Process.whereis(Runner) do
      :telemetry.execute(@hosted_event, %{count: length(Runner.hosted())}, %{})
    end
  catch
    # A runner that is draining for shutdown is not worth a crashed poll.
    :exit, _reason -> :ok
  end
end
