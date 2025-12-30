defmodule Tuist.Authentication.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist authentication events
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :tuist_authentication_event_metrics,
      [
        counter(
          [:tuist, :authentication, :token_refresh, :error, :total],
          event_name: [:analytics, :authentication, :token_refresh, :error],
          description: "The number of token refresh errors.",
          tags: [:cli_version, :reason]
        )
      ]
    )
  end
end
