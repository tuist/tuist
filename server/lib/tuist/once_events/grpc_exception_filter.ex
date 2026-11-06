defmodule Tuist.OnceEvents.GRPCExceptionFilter do
  @moduledoc """
  Decides which exceptions the Once events gRPC listener reports as errors.

  elixir-grpc rejects a call through a `GRPC.RPCError`, raised or returned, and
  its Cowboy adapter logs every one at error level, whatever its status. A
  refused credential, a project the caller cannot reach, or a rate-limited
  caller is the client's problem, so those stay out of error reporting and are
  counted instead (`Tuist.Telemetry.event_name_once_events_refused/0`). Any other
  status, and every unexpected exception, is still reported.
  """

  alias GRPC.Server.Adapters.ReportException

  @client_refusals [
    GRPC.Status.unauthenticated(),
    GRPC.Status.permission_denied(),
    GRPC.Status.resource_exhausted()
  ]

  def log?(%ReportException{reason: %GRPC.RPCError{status: status}}) when status in @client_refusals, do: false
  def log?(%ReportException{}), do: true
end
