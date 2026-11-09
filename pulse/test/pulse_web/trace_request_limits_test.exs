defmodule PulseWeb.TraceRequestLimitsTest do
  use Pulse.Test.Case, async: true

  test "caps log/trace parsing, including encoded route aliases, and restores the connection process" do
    {:max_heap_size, original} = Process.info(self(), :max_heap_size)

    for path <- ["/v1/traces", "/v1/%74races", "/v1/logs", "/v1/%6cogs", "/v1/metrics", "/v1/%6detrics"] do
      conn = Plug.Test.conn(:post, path) |> PulseWeb.TraceRequestLimits.call([])

      assert {:max_heap_size, %{size: 16_000_000, include_shared_binaries: true, kill: true}} =
               Process.info(self(), :max_heap_size)

      assert %{status: 200} = Plug.Conn.send_resp(conn, 200, "")
      assert {:max_heap_size, ^original} = Process.info(self(), :max_heap_size)
    end
  end

  test "other routes/methods retain their existing heap configuration" do
    {:max_heap_size, original} = Process.info(self(), :max_heap_size)

    for {method, path} <- [{:get, "/v1/logs"}, {:get, "/v1/metrics"}, {:get, "/v1/traces"}, {:post, "/mcp"}] do
      conn = Plug.Test.conn(method, path)
      assert conn == PulseWeb.TraceRequestLimits.call(conn, [])
      assert {:max_heap_size, ^original} = Process.info(self(), :max_heap_size)
    end
  end
end
