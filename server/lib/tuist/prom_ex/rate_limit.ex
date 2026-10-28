defmodule Tuist.PromEx.RateLimit do
  @moduledoc false
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:tuist_rate_limit_event_metrics, [
      counter([:tuist, :rate_limit, :shared_failure, :total],
        event_name: [:tuist, :rate_limit, :shared_failure],
        description: "Shared limiter failures by algorithm, outage policy and admission outcome.",
        tags: [:algorithm, :policy, :outcome]
      )
    ])
  end
end
