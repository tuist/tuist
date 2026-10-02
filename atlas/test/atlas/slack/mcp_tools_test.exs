defmodule Atlas.Slack.MCPToolsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.MCP.Proxy
  alias Atlas.Slack.MCPTools
  alias Condukt.Tool

  setup :verify_on_exit!

  test "builds Condukt tools from Atlas MCP descriptors using the supplied claims" do
    user = insert_user!()
    claims = %{"mcp_tool_groups" => []}

    expect(Proxy, :list_hoisted_tools, fn conn ->
      assert conn.assigns.current_user == user
      assert conn.assigns.mcp_claims == claims
      []
    end)

    tools = MCPTools.tools_for(user, claims)

    assert Enum.any?(tools, &(Tool.name(&1) == "list_accounts"))
    refute Enum.any?(tools, &(Tool.name(&1) == "get_finance_overview"))
  end

  test "executes an Atlas MCP tool in process" do
    user = insert_user!()
    _target = insert_account!(%{account_key: "account:target", name: "Target", segment: :customer})
    _other = insert_account!(%{account_key: "account:other", name: "Other", segment: :customer})

    expect(Proxy, :list_hoisted_tools, fn _conn -> [] end)

    list_accounts =
      user
      |> MCPTools.tools_for(%{"mcp_tool_groups" => []})
      |> Enum.find(&(Tool.name(&1) == "list_accounts"))

    assert {:ok, text} = Tool.execute(list_accounts, %{"query" => "Target"}, %{assigns: %{}})

    assert %{"accounts" => [%{"name" => "Target"}], "count" => 1} = JSON.decode!(text)
  end

  test "returns MCP tool errors without raising" do
    user = insert_user!(%{role: :employee})

    expect(Proxy, :list_hoisted_tools, fn _conn -> [] end)

    get_finance_overview =
      user
      |> MCPTools.tools_for(%{"mcp_tool_groups" => ["finance"]})
      |> Enum.find(&(Tool.name(&1) == "get_finance_overview"))

    assert {:error, message} = Tool.execute(get_finance_overview, %{}, %{assigns: %{}})
    assert message =~ "Finance tools require the finance:read scope."
  end
end
