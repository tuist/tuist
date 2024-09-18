defmodule Tuist.Finch.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Finch library.
  For more context, see the documentation for Finch metrics: https://hexdocs.pm/finch/Finch.Telemetry.html
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_finch_queue_stop,
        [
          counter(
            [:tuist, :finch, :get, :connection, :total],
            event_name: [:finch, :queue, :stop],
            description:
              "The total retrievals of HTTP connections from the Finch connection pool."
          ),
          distribution(
            [:tuist, :finch, :get, :connection, :duration, :miliseconds],
            event_name: [:finch, :queue, :stop],
            description:
              "The duration a request has been in the queue for, waiting for an HTTP connection from the Finch connection pool.",
            measurement: :duration,
            unit: :millisecond,
            reporter_options: [
              buckets: exponential!(50, 2, 15)
            ]
          )
        ]
      )
    ]
  end
end
