defmodule Tuist.OnceEvents.GRPCEndpoint do
  @moduledoc """
  gRPC endpoint hosting `Once.Events.V1.RunEventService`.

  Bound to a separate port from the Phoenix HTTP endpoint so an HTTP/2
  gRPC accept path never contends with HTTP/1.1 accept queues. The
  hostname split lives at the ingress (`build.tuist.dev` vs `tuist.dev`);
  inside the pod it is one port for HTTP, one port for gRPC.
  """
  use GRPC.Endpoint

  intercept(GRPC.Server.Interceptors.Logger)

  run(Tuist.OnceEvents.RunEventService)
end
