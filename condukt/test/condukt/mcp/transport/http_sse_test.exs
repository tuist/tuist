defmodule Condukt.MCP.Transport.HttpSSETest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.{JSONRPC, Server}
  alias Condukt.MCP.Transport.HttpSSE

  test "uses the injected POST request function for legacy HTTP+SSE messages" do
    test_pid = self()

    sse_request = fn transport, _url, _headers, _opts ->
      send(test_pid, {:sse_connected, self()})

      receive do
        :publish_endpoint ->
          send(transport, {:sse_chunk, "event: endpoint\ndata: http://127.0.0.1:9/messages\n\n"})
      end

      Process.sleep(:infinity)
    end

    http_request = fn url, envelope, _headers ->
      send(test_pid, {:legacy_post, url, envelope})
      {:ok, 202}
    end

    server = %Server{
      name: "legacy",
      transport: {:http_sse, url: "http://127.0.0.1:9/sse"}
    }

    transport =
      start_supervised!({HttpSSE, server: server, owner: self(), sse_request: sse_request, http_request: http_request})

    assert_receive {:sse_connected, sse_task}, 1_000

    # Exercise the queue before endpoint discovery without racing the SSE task.
    queued_request = JSONRPC.request(1, "tools/list", %{})
    assert :ok = HttpSSE.send_message(transport, queued_request)
    refute_received {:legacy_post, _, _}

    send(sse_task, :publish_endpoint)
    assert_receive {:legacy_post, "http://127.0.0.1:9/messages", ^queued_request}, 1_000

    result = tools_result()
    send(transport, {:sse_chunk, sse_response(1, result)})
    assert_receive {:mcp_message, {:response, 1, {:ok, ^result}}}, 1_000

    # Once the endpoint is known, requests must post without another endpoint event.
    request = JSONRPC.request(2, "tools/list", %{})
    assert :ok = HttpSSE.send_message(transport, request)
    assert_received {:legacy_post, "http://127.0.0.1:9/messages", ^request}

    send(transport, {:sse_chunk, sse_response(2, result)})
    assert_receive {:mcp_message, {:response, 2, {:ok, ^result}}}, 1_000
  end

  defp tools_result do
    %{
      "tools" => [
        %{
          "name" => "echo",
          "description" => "Echoes a value.",
          "inputSchema" => %{"type" => "object", "properties" => %{}}
        }
      ]
    }
  end

  defp sse_response(id, result) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
    "event: message\ndata: #{body}\n\n"
  end
end
