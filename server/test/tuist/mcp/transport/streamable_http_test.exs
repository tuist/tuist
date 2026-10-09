defmodule Tuist.MCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Tuist.MCP.Transport.StreamableHTTP

  defmodule Server do
    @moduledoc false
    def server, do: EMCP.Server.new(name: "test", version: "1", instructions: "Test discovery")
  end

  test "legacy clients initialize without allocating a session" do
    response = request("initialize", %{"protocolVersion" => "2025-06-18", "capabilities" => %{}})
    assert response.status == 200
    assert JSON.decode!(response.resp_body)["result"]["protocolVersion"] == "2025-06-18"
    assert get_resp_header(response, "mcp-session-id") == []
  end

  test "legacy requests work independently of initialization and stale session identifiers" do
    for session <- [nil, "from-another-instance", "expired"] do
      response = request("tools/list", %{}, if(session, do: [{"mcp-session-id", session}], else: []))
      assert response.status == 200
      assert JSON.decode!(response.resp_body)["result"]["tools"] == []
      assert get_resp_header(response, "mcp-session-id") == []
    end
  end

  test "does not expose session lifecycle endpoints" do
    for method <- [:get, :delete] do
      response = method |> conn("/mcp") |> StreamableHTTP.call(server: Server, allowed_origins: [])
      assert response.status == 405
      assert get_resp_header(response, "allow") == ["POST"]
    end
  end

  test "rejects untrusted origins and invalid tool parameters" do
    assert request("tools/list", %{}, [{"origin", "https://attacker.example"}]).status == 403
    assert request("tools/list", %{}, [{"origin", "https://tuist.example"}]).status == 200
    assert request("tools/call", %{}).status == 400
    assert request("tools/call", %{"name" => "absent", "arguments" => []}).status == 400
  end

  test "retains the modern transport and its server discovery response" do
    response =
      request(
        "server/discover",
        %{
          "_meta" => %{"io.modelcontextprotocol/protocolVersion" => "2026-07-28"}
        },
        [{"mcp-protocol-version", "2026-07-28"}, {"mcp-method", "server/discover"}]
      )

    assert response.status == 200
    assert [content_type] = get_resp_header(response, "content-type")
    assert content_type =~ "text/event-stream"
    [_, json] = String.split(response.resp_body, "data: ", parts: 2)
    result = JSON.decode!(String.trim(json))["result"]
    assert result["resultType"] == "complete"
    assert result["instructions"] == "Test discovery"
    assert result["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "test"
    assert get_resp_header(response, "mcp-session-id") == []
  end

  defp request(method, params, headers \\ []) do
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
    conn = :post |> conn("/mcp") |> Map.put(:body_params, body)
    conn = Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
    StreamableHTTP.call(conn, server: Server, allowed_origins: ["https://tuist.example"])
  end
end
