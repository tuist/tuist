defmodule Condukt.MCP.Transport.StdioTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.{Client, Server}

  @echo_script Path.expand("../../../support/fixtures/mcp/echo_server.exs", __DIR__)

  setup do
    elixir = System.find_executable("elixir") || flunk("elixir binary not on PATH")
    {:ok, %{elixir: elixir}}
  end

  defp server_for(elixir) do
    %Server{
      name: "echo",
      transport: {:stdio, command: elixir, args: [@echo_script]},
      init_timeout: 15_000
    }
  end

  test "completes the initialize handshake and lists tools", %{elixir: elixir} do
    {:ok, client} = Client.start_link(server_for(elixir))

    tools = Client.tools(client)
    assert Enum.find(tools, &(&1["name"] == "echo"))
    assert Enum.find(tools, &(&1["name"] == "fail"))

    Client.stop(client)
  end

  test "calls a tool and receives the rendered text content", %{elixir: elixir} do
    {:ok, client} = Client.start_link(server_for(elixir))

    assert {:ok, "echo: hello"} = Client.call_tool(client, "echo", %{"value" => "hello"})

    Client.stop(client)
  end

  test "surfaces isError responses as {:error, _}", %{elixir: elixir} do
    {:ok, client} = Client.start_link(server_for(elixir))

    assert {:error, "boom"} = Client.call_tool(client, "fail", %{})

    Client.stop(client)
  end

  test "fails fast when the executable does not exist" do
    server = %Server{
      name: "missing",
      transport: {:stdio, command: "no-such-binary-on-path-xyzzy", args: []},
      init_timeout: 2_000
    }

    assert {:error, {:transport_failed, {:executable_not_found, "no-such-binary-on-path-xyzzy", :enoent}}} =
             Client.start_link(server)
  end
end
