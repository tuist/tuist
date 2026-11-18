defmodule Condukt.MCP.Transport.StreamableHttpTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.{Client, Server}

  defp fake_http_request(parent) do
    fn _url, envelope, headers ->
      send(parent, {:streamable_request, envelope, normalize_headers(headers)})

      response =
        case envelope do
          %{"id" => id, "method" => "initialize"} ->
            json_response(id, initialize_result(), session_id: "test-session")

          %{"id" => id, "method" => "tools/list"} ->
            json_response(id, %{
              "tools" => [
                %{
                  "name" => "ping",
                  "description" => "Returns pong.",
                  "inputSchema" => %{"type" => "object", "properties" => %{}}
                }
              ]
            })

          %{"id" => id, "method" => "tools/call", "params" => %{"name" => "ping"}} ->
            json_response(id, %{
              "content" => [%{"type" => "text", "text" => "pong"}],
              "isError" => false
            })

          %{"method" => "notifications/" <> _} ->
            %{status: 202, headers: [], body: ""}

          _ ->
            %{status: 400, headers: [], body: ""}
        end

      {:ok, response.status, response.headers, response.body}
    end
  end

  defp initialize_result do
    %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "serverInfo" => %{"name" => "fake", "version" => "1.0"}
    }
  end

  defp json_response(id, result, opts \\ []) do
    body = JSON.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})

    headers =
      [{"content-type", "application/json"}]
      |> maybe_session(Keyword.get(opts, :session_id))

    %{status: 200, headers: headers, body: body}
  end

  defp maybe_session(headers, nil), do: headers
  defp maybe_session(headers, id), do: [{"mcp-session-id", id} | headers]

  defp normalize_headers(headers) do
    Enum.map(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  test "completes the handshake, captures the session id, and routes tool calls" do
    parent = self()

    server = %Server{
      name: "fake",
      transport: {:streamable_http, url: "https://fake.example.com/mcp"}
    }

    {:ok, client} = Client.start_link(server, http_request: fake_http_request(parent))

    assert_receive {:streamable_request, %{"method" => "initialize"}, init_headers}, 1_000
    refute Enum.any?(init_headers, fn {k, _} -> k == "mcp-session-id" end)

    assert_receive {:streamable_request, %{"method" => "notifications/initialized"}, notif_headers}, 1_000
    assert {"mcp-session-id", "test-session"} in notif_headers

    assert_receive {:streamable_request, %{"method" => "tools/list"}, _}, 1_000

    assert [%{"name" => "ping"}] = Client.tools(client)

    assert {:ok, "pong"} = Client.call_tool(client, "ping", %{})
    assert_receive {:streamable_request, %{"method" => "tools/call"}, call_headers}, 1_000
    assert {"mcp-session-id", "test-session"} in call_headers

    Client.stop(client)
  end

  test "supports SSE-encoded responses for a single request" do
    parent = self()

    sse_request_fn = fn _url, envelope, headers ->
      send(parent, {:streamable_request, envelope, normalize_headers(headers)})

      case envelope do
        %{"id" => id, "method" => "initialize"} ->
          body =
            "event: message\ndata: " <>
              JSON.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => initialize_result()}) <>
              "\n\n"

          {:ok, 200, [{"content-type", "text/event-stream"}, {"mcp-session-id", "sse-session"}], body}

        %{"id" => id, "method" => "tools/list"} ->
          body =
            "event: message\ndata: " <>
              JSON.encode!(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{
                  "tools" => [
                    %{"name" => "noop", "inputSchema" => %{"type" => "object", "properties" => %{}}}
                  ]
                }
              }) <>
              "\n\n"

          {:ok, 200, [{"content-type", "text/event-stream"}], body}

        %{"method" => "notifications/" <> _} ->
          {:ok, 202, [], ""}
      end
    end

    server = %Server{name: "fake", transport: {:streamable_http, url: "https://fake.example.com/mcp"}}

    {:ok, client} = Client.start_link(server, http_request: sse_request_fn)

    assert [%{"name" => "noop"}] = Client.tools(client)
    Client.stop(client)
  end

  test "uses bearer auth headers when configured" do
    parent = self()

    fetch_env = fn
      "FAKE_TOKEN" -> {:ok, "token-value"}
      _ -> :error
    end

    server = %Server{
      name: "fake",
      transport: {:streamable_http, url: "https://fake.example.com/mcp"},
      auth: {:bearer, {:env, "FAKE_TOKEN"}}
    }

    {:ok, client} = Client.start_link(server, http_request: fake_http_request(parent), fetch_env: fetch_env)

    assert_receive {:streamable_request, %{"method" => "initialize"}, headers}, 1_000
    assert {"authorization", "Bearer token-value"} in headers

    Client.stop(client)
  end

  test "returns an error when a tool call exceeds its request timeout" do
    http_request = fn _url, envelope, _headers ->
      case envelope do
        %{"id" => id, "method" => "initialize"} ->
          response = json_response(id, initialize_result())
          {:ok, response.status, response.headers, response.body}

        %{"id" => id, "method" => "tools/list"} ->
          response =
            json_response(id, %{
              "tools" => [
                %{
                  "name" => "slow",
                  "description" => "Responds too slowly.",
                  "inputSchema" => %{"type" => "object", "properties" => %{}}
                }
              ]
            })

          {:ok, response.status, response.headers, response.body}

        %{"method" => "notifications/" <> _} ->
          {:ok, 202, [], ""}

        %{"method" => "tools/call"} ->
          Process.sleep(200)
          {:ok, 202, [], ""}
      end
    end

    server = %Server{
      name: "fake",
      transport: {:streamable_http, url: "https://fake.example.com/mcp"}
    }

    {:ok, client} = Client.start_link(server, http_request: http_request)

    assert {:error, :request_timeout} = Client.call_tool(client, "slow", %{}, timeout: 20)

    Client.stop(client)
  end
end
