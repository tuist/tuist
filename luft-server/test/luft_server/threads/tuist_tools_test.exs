defmodule LuftServer.Threads.TuistToolsTest do
  use ExUnit.Case, async: true

  alias LuftServer.Threads.TuistTools

  test "stream collector only finishes on a correlated, terminated response" do
    envelope = Jason.encode!(%{jsonrpc: "2.0", id: 3, result: %{tools: []}})
    frame = "event: message\r\ndata: " <> envelope
    refute TuistTools.response_complete?(frame, 3)
    refute TuistTools.response_complete?(frame <> "\r\n\r\n", 4)
    assert TuistTools.response_complete?(frame <> "\r\n\r\n", 3)
    assert TuistTools.response_complete?(envelope, 3)
  end

  test "definitive JSON-RPC errors terminate reads but ambiguous envelopes do not" do
    error = %{jsonrpc: "2.0", id: 1, error: %{code: -1, message: "private"}}
    assert error |> Jason.encode!() |> TuistTools.response_complete?(1)
    refute error |> Map.put(:result, %{}) |> Jason.encode!() |> TuistTools.response_complete?(1)
    refute TuistTools.response_complete?("not JSON", 1)
  end
end
