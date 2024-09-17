defmodule Tuist.Req.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist command events.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_http_requests_event_metrics,
        [
          counter(
            [:tuist, :http, :requests, :total],
            event_name: [:req, :request, :pipeline, :stop],
            description: "The total HTTP requests sent by Tuist",
            tags: [:url, :method, :status]
          ),
          distribution(
            [:tuist, :http, :requests, :duration, :miliseconds],
            event_name: [:req, :request, :pipeline, :stop],
            description: "The distribution of HTTP requests duration in miliseconds",
            measurement: :duration,
            unit: :millisecond,
            tags: [:url, :method, :status],
            reporter_options: [
              buckets: exponential!(50, 2, 15)
            ]
          )
        ]
      )
    ]
  end
end
