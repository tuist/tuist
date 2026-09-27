defmodule Tuist.MCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Tuist.MCP.Transport.StreamableHTTP

  @version "2026-07-28"
  @meta %{
    "io.modelcontextprotocol/protocolVersion" => @version,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defmodule Server do
    @moduledoc false
    def server, do: EMCP.Server.new(name: "test", version: "1", instructions: "Test discovery")
  end

  test "discovers the server without initialization or a session" do
    conn = request("server/discover")
    result = JSON.decode!(conn.resp_body)["result"]
    assert conn.status == 200
    assert result["resultType"] == "complete"
    assert @version in result["supportedVersions"]
    assert result["instructions"] == "Test discovery"
    assert result["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "test"
    assert get_resp_header(conn, "mcp-session-id") == []
    refute Map.has_key?(result["capabilities"]["tools"], "listChanged")
  end

  test "accepts independent requests with stale session identifiers" do
    for session <- [nil, "from-another-instance", "expired"] do
      conn = request("tools/list", headers: if(session, do: [{"mcp-session-id", session}], else: []))
      assert conn.status == 200
      assert JSON.decode!(conn.resp_body)["result"]["tools"] == []
      assert get_resp_header(conn, "mcp-session-id") == []
    end
  end

  test "rejects missing required per-request capabilities" do
    conn = request("tools/list", meta: Map.delete(@meta, "io.modelcontextprotocol/clientCapabilities"))
    assert_error(conn, 400, -32_602)
  end

  test "rejects version and method header mismatches" do
    assert_error(request("tools/list", headers: [{"mcp-protocol-version", "2025-06-18"}]), 400, -32_020)
    assert_error(request("tools/list", headers: [{"mcp-method", "tools/call"}]), 400, -32_020)
  end

  test "requires the tool name header and compares decoded values" do
    assert_error(request("tools/call", params: %{"name" => "absent"}), 400, -32_020)
    conn = request("tools/call", params: %{"name" => "absent"}, headers: [{"mcp-name", "=?base64?YWJzZW50?="}])
    assert_error(conn, 400, -32_602)
    assert JSON.decode!(conn.resp_body)["error"]["message"] == "Tool not found: absent"
  end

  test "reports supported versions on an unsupported version" do
    conn = request("tools/list", headers: [{"mcp-protocol-version", "2099-01-01"}])
    assert_error(conn, 400, -32_022)
    assert @version in JSON.decode!(conn.resp_body)["error"]["data"]["supported"]
  end

  test "reports unknown methods and rejects modern initialization" do
    assert_error(request("unknown/method"), 404, -32_601)
    assert_error(request("initialize"), 404, -32_601)
  end

  test "rejects untrusted origins" do
    assert_error(request("tools/list", headers: [{"origin", "https://attacker.example"}]), 403, -32_600)
    assert request("tools/list", headers: [{"origin", "https://tuist.example"}]).status == 200
  end

  test "does not expose session lifecycle endpoints" do
    for method <- [:get, :delete] do
      conn = method |> conn("/mcp") |> StreamableHTTP.call(server: Server, allowed_origins: [])
      assert conn.status == 405
      assert get_resp_header(conn, "allow") == ["POST"]
    end
  end

  test "rejects invalid tool parameters without crashing" do
    assert_error(request("tools/call"), 400, -32_602)
    assert_error(request("tools/call", params: %{"name" => "absent", "arguments" => []}), 400, -32_602)
  end

  defp request(method, opts \\ []) do
    params = Map.put(Keyword.get(opts, :params, %{}), "_meta", Keyword.get(opts, :meta, @meta))
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
    conn = :post |> conn("/mcp") |> Map.put(:body_params, body)
    conn = conn |> put_req_header("mcp-protocol-version", @version) |> put_req_header("mcp-method", method)

    conn =
      Enum.reduce(Keyword.get(opts, :headers, []), conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    StreamableHTTP.call(conn, server: Server, allowed_origins: ["https://tuist.example"])
  end

  defp assert_error(conn, status, code) do
    assert conn.status == status
    assert JSON.decode!(conn.resp_body)["error"]["code"] == code
  end
end
