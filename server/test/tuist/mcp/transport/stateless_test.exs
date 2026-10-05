defmodule Tuist.MCP.Transport.StatelessTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Tuist.MCP.Server
  alias Tuist.MCP.Transport.Stateless
  alias Tuist.MCP.Transport.StreamableHTTP

  @version "2026-07-28"

  test "discovers the stateless lifecycle without a session" do
    response = request("server/discover")

    assert response.status == 200
    assert get_resp_header(response, "mcp-session-id") == []

    assert %{
             "resultType" => "complete",
             "supportedVersions" => [@version],
             "capabilities" => %{"tools" => %{}, "prompts" => %{}, "events" => %{}},
             "_meta" => %{"io.modelcontextprotocol/serverInfo" => %{"name" => "tuist"}}
           } = result_body(response)["result"]
  end

  test "lists existing tools through the stateless lifecycle" do
    response = request("tools/list")

    assert response.status == 200
    assert %{"resultType" => "complete", "tools" => tools} = result_body(response)["result"]
    assert Enum.any?(tools, &(&1["name"] == "get_test_case"))
  end

  test "advertises only event types that can be delivered" do
    response = request("events/list")

    events = result_body(response)["result"]["events"]

    assert Enum.sort(Enum.map(events, & &1["name"])) == [
             "build.failed",
             "ci_job.failed",
             "test_case.marked_flaky",
             "test_run.failed"
           ]

    assert Enum.all?(events, &(&1["delivery"] == ["webhook"]))
  end

  test "rejects a method header that differs from the request" do
    response = request("tools/list", "prompts/list")

    assert response.status == 400
    assert result_body(response)["error"]["code"] == -32_020
  end

  test "rejects an untrusted request origin" do
    params = %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version}}
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "server/discover", "params" => params}

    response =
      :post
      |> conn("/mcp", JSON.encode!(body))
      |> put_req_header("mcp-protocol-version", @version)
      |> put_req_header("mcp-method", "server/discover")
      |> put_req_header("origin", "https://untrusted.example")
      |> Map.put(:body_params, body)
      |> Stateless.call(server: Server)

    assert response.status == 403
    assert result_body(response)["error"]["message"] == "Forbidden origin"
  end

  test "reports an unsupported modern version with supported versions" do
    params = %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => "2027-01-01"}}
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "server/discover", "params" => params}

    response =
      :post
      |> conn("/mcp", JSON.encode!(body))
      |> put_req_header("mcp-protocol-version", "2027-01-01")
      |> put_req_header("mcp-method", "server/discover")
      |> Map.put(:body_params, body)
      |> StreamableHTTP.call(server: Server)

    assert response.status == 400
    assert %{"code" => -32_022, "data" => %{"requested" => "2027-01-01"}} = result_body(response)["error"]
  end

  test "leaves legacy requests on the existing transport" do
    response =
      :get
      |> conn("/mcp")
      |> StreamableHTTP.call(server: Server)

    assert response.status == 406
  end

  defp request(method, header_method \\ nil) do
    params = %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => @version}}
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

    :post
    |> conn("/mcp", JSON.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("mcp-protocol-version", @version)
    |> put_req_header("mcp-method", header_method || method)
    |> Map.put(:body_params, body)
    |> Stateless.call(server: Server)
  end

  defp result_body(conn) do
    case String.split(conn.resp_body, "data: ", parts: 2) do
      [_, json] -> json |> String.trim() |> JSON.decode!()
      [json] -> JSON.decode!(json)
    end
  end
end
