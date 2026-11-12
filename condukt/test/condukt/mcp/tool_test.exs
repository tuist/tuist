defmodule Condukt.MCP.ToolTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.{Server, Tool}

  defmodule ClientStub do
    use GenServer

    def start_link(tools) do
      GenServer.start_link(__MODULE__, tools)
    end

    @impl true
    def init(tools), do: {:ok, tools}

    @impl true
    def handle_call(:tools, _from, tools), do: {:reply, tools, tools}

    def handle_call({:call_tool, name, args, _timeout}, _from, tools) do
      {:reply, {:ok, %{name: name, args: args}}, tools}
    end
  end

  test "uses provider-safe names while dispatching original MCP tool names" do
    client =
      start_supervised!(
        {ClientStub,
         [
           %{
             "name" => "list.accounts",
             "description" => "List accounts",
             "inputSchema" => %{"type" => "object"}
           }
         ]}
      )

    server = %Server{
      name: "atlas",
      transport: {:streamable_http, url: "https://example.com/mcp"},
      request_timeout: 1_000
    }

    [tool] = Tool.inline_tools(client, server)

    assert tool.name == "atlas_list_accounts"
    assert tool.call.(%{"limit" => 10}, %{}) == {:ok, %{name: "list.accounts", args: %{"limit" => 10}}}
  end

  test "truncates long generated names to the provider limit" do
    client =
      start_supervised!(
        {ClientStub,
         [
           %{
             "name" => String.duplicate("tool-", 20),
             "inputSchema" => %{"type" => "object"}
           }
         ]}
      )

    server = %Server{
      name: String.duplicate("server-", 10),
      transport: {:streamable_http, url: "https://example.com/mcp"}
    }

    [tool] = Tool.inline_tools(client, server)

    assert byte_size(tool.name) == 64
    assert tool.name =~ ~r/^[A-Za-z0-9_-]+$/
  end
end
