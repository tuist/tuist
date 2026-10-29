defmodule Atlas.Orbit.ToolPolicyTest do
  use ExUnit.Case, async: true

  alias Atlas.MCP.Server
  alias Atlas.MCP.Tool
  alias Atlas.Orbit.ToolPolicy

  @tool_names Server.tool_modules() |> Enum.map(&Tool.descriptor/1) |> MapSet.new(& &1["name"])

  test "every allowed tool exists, is a read, and declares known scopes" do
    for {name, scopes} <- ToolPolicy.policy() do
      assert MapSet.member?(@tool_names, name), "#{name} is not an Atlas MCP tool"
      assert String.starts_with?(name, ["get_", "list_", "search_", "recall_"]), "#{name} is not a read tool"
      assert Enum.all?(scopes, &(&1 in Atlas.Authorization.all_scopes())), "#{name} declares an unknown scope"
    end
  end

  test "credential, secret, egress, raw-query, memory-write and side-effect tools are never allowed" do
    for name <- ToolPolicy.never() do
      refute Map.has_key?(ToolPolicy.policy(), name), "#{name} must never be mounted"
    end

    refute Enum.any?(Map.keys(ToolPolicy.policy()), &String.contains?(&1, "__")), "upstream proxy tools are excluded"
  end

  test "offers a tool only when every reader holds its scopes" do
    names = fn scopes -> scopes |> MapSet.new() |> ToolPolicy.available() |> Enum.map(& &1["name"]) end

    assert "list_tasks" in names.([])
    refute "list_finance_transactions" in names.([])
    assert "list_finance_transactions" in names.(["finance:read"])
    refute "list_briefs" in names.(["briefs:read"])
    assert "list_briefs" in names.(["briefs:read", "admin:read"])
  end

  test "the offered nudge schema rejects the reported state-only call and accepts each account identifier" do
    descriptor = Enum.find(ToolPolicy.available(MapSet.new(["accounts:read"])), &(&1["name"] == "list_account_nudges"))
    schema = ExJsonSchema.Schema.resolve(descriptor["inputSchema"])
    assert {:error, _} = ExJsonSchema.Validator.validate(schema, %{"state" => "pending_post"})

    for identifier <- ~w(account_id account_key handle) do
      assert :ok = ExJsonSchema.Validator.validate(schema, %{identifier => "example", "state" => "pending_post"})
    end

    assert descriptor["description"] =~ "state alone is not sufficient"
  end
end
