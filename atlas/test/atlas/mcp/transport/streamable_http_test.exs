defmodule Atlas.MCP.Transport.StreamableHTTPTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias Atlas.MCP.Server
  alias Atlas.MCP.Transport.StreamableHTTP

  test "initializes without issuing a replica-local session" do
    conn = json_post(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})
    assert conn.status == 200
    assert get_resp_header(conn, "mcp-session-id") == []
    assert is_nil(Server.server().session_store)

    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{"protocolVersion" => _, "serverInfo" => %{"name" => "atlas"}}
           } = JSON.decode!(conn.resp_body)
  end

  test "dispatches requests without initialization or a session header" do
    conn = json_post(%{"jsonrpc" => "2.0", "id" => 2, "method" => "ping"})
    assert conn.status == 200
    assert JSON.decode!(conn.resp_body) == %{"jsonrpc" => "2.0", "id" => 2, "result" => %{}}
  end

  test "ignores legacy session headers after routing to a new replica" do
    conn =
      json_post(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}, [{"mcp-session-id", "old-pod-session"}])

    assert conn.status == 200
    assert is_list(JSON.decode!(conn.resp_body)["result"]["tools"])
  end

  test "marks requests as coming from the MCP interface" do
    expect(Server, :handle_message, fn conn, request ->
      assert conn.assigns.audit_interface == "mcp"
      call_original(Server, :handle_message, [conn, request])
    end)

    assert json_post(%{"jsonrpc" => "2.0", "id" => 2, "method" => "ping"}).status == 200
  end

  test "accepts notifications without a response body or session" do
    conn = json_post(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    assert conn.status == 202
    assert conn.resp_body == ""
  end

  test "does not offer session-bound SSE connections or session deletion" do
    for method <- [:get, :delete] do
      conn =
        method |> conn("/mcp") |> put_req_header("accept", "text/event-stream") |> StreamableHTTP.call(server: Server)

      assert conn.status == 405
      assert get_resp_header(conn, "allow") == ["POST"]
    end
  end

  test "rejects invalid JSON bodies and non-object JSON" do
    for body <- ["not-json", "[]", "null", "1"] do
      conn =
        :post
        |> conn("/mcp", body)
        |> put_req_header("content-type", "application/json")
        |> StreamableHTTP.call(server: Server)

      assert conn.status == 400
    end
  end

  test "rejects forbidden origins when origin validation is enabled" do
    conn =
      json_post(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}, [{"origin", "https://evil.example"}],
        validate_origin: true,
        allowed_origins: ["https://atlas.example"]
      )

    assert conn.status == 403
    assert %{"error" => %{"code" => -32_600, "message" => "Forbidden origin"}} = JSON.decode!(conn.resp_body)
  end

  test "rejects a protocol version the server does not speak" do
    conn =
      json_post(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}, [{"mcp-protocol-version", "2024-11-05"}])

    assert conn.status == 400

    assert %{
             "error" => %{
               "code" => -32_600,
               "message" => "Unsupported MCP protocol version: 2024-11-05",
               "data" => %{"supported" => ["2025-06-18", "2025-03-26"]}
             }
           } = JSON.decode!(conn.resp_body)
  end

  test "accepts a supported protocol version header" do
    conn =
      json_post(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}, [{"mcp-protocol-version", "2025-06-18"}])

    assert conn.status == 200
  end

  test "normalizes origins before matching" do
    assert StreamableHTTP.origin_allowed?("https://Atlas.Example.", ["https://atlas.example"])
    assert StreamableHTTP.origin_allowed?("https://atlas.example", ["atlas.example"])
    refute StreamableHTTP.origin_allowed?("https://evil.example", ["https://atlas.example"])
  end

  defp json_post(message, headers \\ [], opts \\ []) do
    :post
    |> conn("/mcp", JSON.encode!(message))
    |> put_req_header("content-type", "application/json")
    |> put_headers(headers)
    |> StreamableHTTP.call(Keyword.merge([server: Server], opts))
  end

  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
  end
end
