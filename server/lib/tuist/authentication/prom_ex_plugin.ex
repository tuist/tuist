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
        ),
        counter(
          [:tuist, :authentication, :oidc, :scope_withheld, :total],
          event_name: [:tuist, :oidc, :scope_withheld],
          description: "The number of scopes withheld from OIDC-exchanged tokens because a scope rule didn't match.",
          tags: [:scope, :level, :field]
        )
      ]
    )
  end
end
