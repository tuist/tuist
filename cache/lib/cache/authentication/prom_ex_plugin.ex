defmodule Cache.Authentication.PromExPlugin do
  @moduledoc """
  Prometheus metrics for authentication operations.

  Tracks auth cache performance, server API requests, and authorization methods.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_auth_event_metrics, [
      counter(
        [:cache, :auth, :cache, :hit, :total],
        event_name: [:cache, :auth, :cache, :hit],
        description: "Auth cache hits."
      ),
      counter(
        [:cache, :auth, :cache, :miss, :total],
        event_name: [:cache, :auth, :cache, :miss],
        description: "Auth cache misses."
      ),
      counter(
        [:cache, :auth, :server, :request, :total],
        event_name: [:cache, :auth, :server, :request],
        description: "Server API requests for project access validation."
      ),
      counter(
        [:cache, :auth, :server, :error, :total],
        event_name: [:cache, :auth, :server, :error],
        description: "Server request errors.",
        tags: [:reason],
        tag_values: fn metadata -> %{reason: to_string(Map.get(metadata, :reason, :unknown))} end
      ),
      distribution(
        [:cache, :auth, :server, :duration, :milliseconds],
        event_name: [:cache, :auth, :server, :response],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Server request duration.",
        reporter_options: [buckets: [10, 25, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      counter(
        [:cache, :auth, :authorized, :total],
        event_name: [:cache, :auth, :authorized],
        description: "Authorized requests.",
        tags: [:method],
        tag_values: fn metadata -> %{method: to_string(Map.get(metadata, :method, :unknown))} end
      )
    ])
  end
end
