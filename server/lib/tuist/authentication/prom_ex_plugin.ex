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
        counter([:tuist, :authentication, :bcrypt_verification, :total],
          event_name: [:tuist, :authentication, :bcrypt_verification],
          description: "The number of uncached token bcrypt verifications on this replica.",
          tags: [:outcome]
        ),
        distribution([:tuist, :authentication, :bcrypt_verification, :duration, :milliseconds],
          event_name: [:tuist, :authentication, :bcrypt_verification],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Time spent verifying uncached token bcrypt proofs.",
          tags: [:outcome],
          reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 5000]]
        )
      ]
    )
  end
end
