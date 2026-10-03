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

  @unauthenticated GRPC.Status.unauthenticated()

  # The adapter logs every raised `GRPC.RPCError` at error level, which reaches
  # Sentry. A rejected credential or project is the client's problem and the
  # client already receives the status, so only server faults are logged.
  def log_exception?(%GRPC.Server.Adapters.ReportException{reason: %GRPC.RPCError{status: @unauthenticated}}), do: false
  def log_exception?(_exception), do: true
end
