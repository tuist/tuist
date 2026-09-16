defmodule Atlas.MCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Atlas.MCP.Server
  alias Atlas.MCP.Transport.StreamableHTTP
  alias EMCP.SessionStore.ETS

  test "initializes an MCP session" do
    {session_id, body} = initialize_session()

    assert byte_size(session_id) == 32

    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{
               "protocolVersion" => _protocol_version,
               "serverInfo" => %{"name" => "atlas"}
             }
           } = body
  end

  test "dispatches requests for an existing session" do
    {session_id, _body} = initialize_session()

    conn =
      json_post(%{"jsonrpc" => "2.0", "id" => 2, "method" => "ping"}, [
        {"mcp-session-id", session_id}
      ])

    assert conn.status == 200

    assert JSON.decode!(conn.resp_body) == %{
             "jsonrpc" => "2.0",
             "id" => 2,
             "result" => %{}
           }
  end

  test "returns request responses inline when the session has a stale event stream registration" do
    {session_id, _body} = initialize_session()

    stale_pid = spawn(fn -> :ok end)
    ref = Process.monitor(stale_pid)

    assert_receive {:DOWN, ^ref, :process, ^stale_pid, _reason}

    ETS.register(session_id, stale_pid)

    conn =
      json_post(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}, [
        {"mcp-session-id", session_id}
      ])

    response = JSON.decode!(conn.resp_body)

    assert conn.status == 200
    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 2
    assert is_list(response["result"]["tools"])
  end

  test "accepts notifications for an existing session without a response body" do
    {session_id, _body} = initialize_session()

    conn =
      json_post(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, [
        {"mcp-session-id", session_id}
      ])

    assert conn.status == 202
    assert conn.resp_body == ""
  end

  test "deletes sessions" do
    {session_id, _body} = initialize_session()

    conn =
      :delete
      |> conn("/mcp")
      |> put_req_header("mcp-session-id", session_id)
      |> StreamableHTTP.call(server: Server)

    assert conn.status == 200
    assert JSON.decode!(conn.resp_body) == %{"success" => true}

    conn =
      json_post(
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "ping"},
        [{"mcp-session-id", session_id}],
        recreate_missing_session: false
      )

    assert conn.status == 404
    assert JSON.decode!(conn.resp_body) == %{"error" => "Session not found"}
  end

  test "rejects requests that require a session when the session header is missing" do
    conn = json_post(%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

    assert conn.status == 400
    assert JSON.decode!(conn.resp_body) == %{"error" => "Missing session ID"}
  end

  test "rejects invalid JSON bodies" do
    conn =
      :post
      |> conn("/mcp", "not-json")
      |> put_req_header("content-type", "application/json")
      |> StreamableHTTP.call(server: Server)

    assert conn.status == 400
    assert JSON.decode!(conn.resp_body) == %{"error" => "Invalid JSON"}
  end

  test "rejects forbidden origins when origin validation is enabled" do
    conn =
      :post
      |> conn("/mcp", JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", "https://evil.example")
      |> StreamableHTTP.call(
        server: Server,
        validate_origin: true,
        allowed_origins: ["https://atlas.example"]
      )

    assert conn.status == 403

    assert JSON.decode!(conn.resp_body) == %{
             "jsonrpc" => "2.0",
             "error" => %{"code" => -32_600, "message" => "Forbidden origin"}
           }
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

  defp initialize_session do
    conn = json_post(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})

    assert conn.status == 200
    assert [session_id] = get_resp_header(conn, "mcp-session-id")

    {session_id, JSON.decode!(conn.resp_body)}
  end

  defp json_post(message, headers \\ [], opts \\ []) do
    :post
    |> conn("/mcp", JSON.encode!(message))
    |> put_req_header("content-type", "application/json")
    |> put_headers(headers)
    |> StreamableHTTP.call(Keyword.merge([server: Server], opts))
  end

  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
  end
end
