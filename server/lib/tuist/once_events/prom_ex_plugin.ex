defmodule Tuist.OnceEvents.PromExPlugin do
  @moduledoc """
  Counts calls the Once events gRPC service refuses, by call, by whether the
  refusal happened when the call opened or on the periodic check of an open
  stream, and by status.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :tuist_once_events_event_metrics,
      [
        counter(
          [:tuist, :once_events, :refused, :total],
          event_name: Telemetry.event_name_once_events_refused(),
          description: "Calls to the Once events gRPC service refused for their credential or project.",
          tags: [:rpc, :stage, :status]
        )
      ]
    )
  end
end
