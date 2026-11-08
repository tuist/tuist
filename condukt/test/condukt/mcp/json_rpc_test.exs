defmodule Condukt.MCP.JSONRPCTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.JSONRPC

  describe "request/3" do
    test "builds an envelope with id, method, and optional params" do
      assert %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"} = JSONRPC.request(1, "tools/list")
      assert %{"params" => %{"name" => "x"}} = JSONRPC.request(2, "tools/call", %{"name" => "x"})
    end
  end

  describe "notification/2" do
    test "builds an envelope without an id" do
      env = JSONRPC.notification("notifications/initialized")
      assert env["method"] == "notifications/initialized"
      refute Map.has_key?(env, "id")
    end
  end

  describe "encode_line!/1" do
    test "appends a newline" do
      assert JSONRPC.encode_line!(%{"a" => 1}) == ~s({"a":1}\n)
    end
  end

  describe "classify/1" do
    test "tags successful responses" do
      assert {:response, 7, {:ok, %{"value" => 1}}} =
               JSONRPC.classify(%{"jsonrpc" => "2.0", "id" => 7, "result" => %{"value" => 1}})
    end

    test "tags error responses" do
      env = %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -32_601, "message" => "x"}}
      assert {:response, 1, {:error, %{"code" => -32_601}}} = JSONRPC.classify(env)
    end

    test "tags requests with id" do
      env = %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}
      assert {:request, 1, "ping", nil} = JSONRPC.classify(env)
    end

    test "tags notifications" do
      env = %{"jsonrpc" => "2.0", "method" => "notifications/something", "params" => %{}}
      assert {:notification, "notifications/something", %{}} = JSONRPC.classify(env)
    end

    test "rejects non-jsonrpc envelopes" do
      assert {:error, :invalid_envelope} = JSONRPC.classify(%{"id" => 1, "result" => 1})
    end
  end

  describe "decode_and_classify/1" do
    test "decodes and classifies in one step" do
      assert {:response, 1, {:ok, %{}}} = JSONRPC.decode_and_classify(~s({"jsonrpc":"2.0","id":1,"result":{}}))
    end

    test "returns an error for invalid json" do
      assert {:error, {:decode_failed, _}} = JSONRPC.decode_and_classify("not json")
    end
  end
end
