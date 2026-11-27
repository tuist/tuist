defmodule Tuist.OnceEvents.GRPCEndpoint do
  @moduledoc """
  gRPC endpoint hosting `Once.Events.V1.RunEventService`.

  Bound to a separate port from the Phoenix HTTP endpoint so an HTTP/2
  gRPC accept path never contends with HTTP/1.1 accept queues. The
  hostname split lives at the ingress (`events.tuist.dev` vs `tuist.dev`);
  inside the pod it is one port for HTTP, one port for gRPC.
  """
  use GRPC.Endpoint

  intercept(GRPC.Server.Interceptors.Logger)
  intercept(TuistWeb.RateLimit.OnceEvents)

  run(Tuist.OnceEvents.RunEventService)

  @doc """
  Options for the `GRPC.Server.Supervisor` that serves this endpoint on `port`.
  """
  def server_options(port) do
    [
      endpoint: __MODULE__,
      port: port,
      start_server: true,
      exception_log_filter: {Tuist.OnceEvents.GRPCExceptionFilter, :log?},
      # Caps a call's whole request body, so a run's PublishRunEvents stream
      # included. Matches the events ingress's `proxy-body-size` (50m), which
      # already ends longer streams, so the edge stays the limit runs meet.
      max_body_size: 50 * 1024 * 1024
    ]
  end
end
