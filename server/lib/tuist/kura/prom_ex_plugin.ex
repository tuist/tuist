defmodule Tuist.Kura.PromExPlugin do
  @moduledoc """
  Prometheus metrics for Kura control-plane reconciliation.
  """

  use PromEx.Plugin

  alias Tuist.Kura.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_kura_runner_cache_reconciliation_event_metrics,
        [
          last_value(
            [:tuist, :kura, :runner_cache, :reconciliation, :paused],
            event_name: Telemetry.event_name_runner_cache_reconciliation(),
            measurement: :paused,
            description:
              "Whether runner-cache reconciliation is paused by an unsafe or unavailable feature-flag cohort (1 paused, 0 healthy)."
          )
        ]
      )
    ]
  end
end
