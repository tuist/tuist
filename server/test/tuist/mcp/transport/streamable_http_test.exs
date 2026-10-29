defmodule Tuist.MCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias Tuist.Environment
  alias Tuist.MCP.Transport.StreamableHTTP

  defmodule Server do
    @moduledoc false
    def server, do: EMCP.Server.new(name: "test", version: "1", instructions: "Test discovery")
  end

  defmodule EmptyTool do
    @moduledoc false
    @behaviour EMCP.Tool

    def name, do: "empty_tool"
    def description, do: "Echo empty arguments"
    def input_schema, do: %{"type" => "object"}
    def call(_conn, args), do: EMCP.Tool.response(%{"type" => "text", "text" => JSON.encode!(args)})
  end

  defmodule EmptyPrompt do
    @moduledoc false
    @behaviour EMCP.Prompt

    def name, do: "empty_prompt"
    def description, do: "Echo empty arguments"
    def arguments, do: []

    def template(_conn, args),
      do: %{"messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => JSON.encode!(args)}}]}
  end

  defmodule ArgumentServer do
    @moduledoc false
    def server, do: EMCP.Server.new(name: "arguments", version: "1", tools: [EmptyTool], prompts: [EmptyPrompt])
  end

  test "legacy null and absent tool or prompt arguments still dispatch as empty maps" do
    for {method, name} <- [{"tools/call", "empty_tool"}, {"prompts/get", "empty_prompt"}],
        arguments <- [%{}, %{"arguments" => nil}] do
      response = request(method, Map.put(arguments, "name", name), [], server: ArgumentServer)
      assert response.status == 200
      result = JSON.decode!(response.resp_body)["result"]
      content = result["content"] || Enum.map(result["messages"], & &1["content"])
      assert [%{"type" => "text", "text" => "{}"}] = content
    end
  end

  test "both protocol paths default to the app origin rather than the marketing origin" do
    stub(Environment, :app_url, fn opts ->
      if opts[:route_type] == :app, do: "https://self-hosted.example", else: "https://tuist.dev"
    end)

    for {method, params, headers} <- [
          {"tools/list", %{}, []},
          {"server/discover", %{"_meta" => %{"io.modelcontextprotocol/protocolVersion" => "2026-07-28"}},
           [{"mcp-protocol-version", "2026-07-28"}, {"mcp-method", "server/discover"}]}
        ] do
      assert request(method, params, [{"origin", "https://self-hosted.example"} | headers], server: Server).status == 200
      assert request(method, params, [{"origin", "https://attacker.example"} | headers], server: Server).status == 403
    end
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

  defp request(method, params, headers \\ [], opts \\ [server: Server, allowed_origins: ["https://tuist.example"]]) do
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
    conn = :post |> conn("/mcp") |> Map.put(:body_params, body)
    conn = Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
    StreamableHTTP.call(conn, opts)
  end
end
