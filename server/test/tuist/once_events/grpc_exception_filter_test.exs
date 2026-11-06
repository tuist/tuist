defmodule Tuist.OnceEvents.GRPCExceptionFilterTest do
  use ExUnit.Case, async: true

  alias GRPC.Server.Adapters.ReportException
  alias Tuist.OnceEvents.GRPCExceptionFilter

  defp report(error), do: ReportException.new([req: :ok], error)

  test "a refused credential is not reported as a server error" do
    error = GRPC.RPCError.exception(status: :unauthenticated, message: "missing or invalid bearer")

    refute GRPCExceptionFilter.log?(report(error))
  end

  test "a refused project and a rate-limited caller are not reported as server errors" do
    for status <- [:permission_denied, :resource_exhausted] do
      refute GRPCExceptionFilter.log?(report(GRPC.RPCError.exception(status: status))), "#{status} was reported"
    end
  end

  test "statuses that can point at the server are still reported" do
    for status <- [:unknown, :internal, :unavailable, :deadline_exceeded, :invalid_argument] do
      assert GRPCExceptionFilter.log?(report(GRPC.RPCError.exception(status: status))), "#{status} was dropped"
    end
  end

  test "an unexpected crash is still reported" do
    assert GRPCExceptionFilter.log?(report(%RuntimeError{message: "boom"}))
  end
end
