defmodule Tuist.OnceEvents.GRPCEndpointTest do
  use ExUnit.Case, async: true

  alias GRPC.Server.Adapters.ReportException
  alias Tuist.OnceEvents.GRPCEndpoint

  describe "log_exception?/1" do
    test "drops unauthenticated RPC errors" do
      error = GRPC.RPCError.exception(status: :unauthenticated, message: "no access to the requested project")

      refute GRPCEndpoint.log_exception?(ReportException.new([req: :ok], error))
    end

    test "logs other RPC errors" do
      error = GRPC.RPCError.exception(status: :internal, message: "boom")

      assert GRPCEndpoint.log_exception?(ReportException.new([req: :ok], error))
    end

    test "logs unexpected exceptions" do
      assert GRPCEndpoint.log_exception?(ReportException.new([req: :ok], %RuntimeError{message: "boom"}))
    end
  end
end
