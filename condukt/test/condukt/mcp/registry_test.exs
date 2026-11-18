defmodule Condukt.MCP.RegistryTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP
  alias Condukt.MCP.Registry

  test "start_all/2 returns an empty registry for an empty list" do
    assert {:ok, %Registry{entries: []}} = MCP.start_all([])
    assert MCP.tools(%Registry{}) == []
  end

  test "start_all/2 surfaces invalid server specs as a tagged error" do
    assert {:error, {:mcp_start_failed, "x", _}} = MCP.start_all([%{"name" => "x", "transport" => "stdio"}])
  end

  test "stop_all/1 is a no-op for an empty registry" do
    assert :ok = MCP.stop_all(%Registry{})
  end
end
