defmodule Atlas.MCP.Tools.ListAccountsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.ListAccounts

  test "filters by segment" do
    _customer =
      insert_account!(%{name: "Acme", account_key: "acme", segment: :customer, hosting: "self_hosted"})

    _lead = insert_account!(%{name: "Beta", account_key: "beta", segment: :lead})

    {:ok, %{accounts: accounts}} = execute_tool(ListAccounts, nil, %{"segment" => "customer"})

    assert Enum.map(accounts, & &1.name) == ["Acme"]
    assert [%{hosting: "self_hosted"}] = accounts
  end

  test "free-text search matches the account name" do
    _acme = insert_account!(%{name: "Acme", account_key: "acme-1"})
    _other = insert_account!(%{name: "Globex", account_key: "globex-1"})

    {:ok, %{accounts: accounts}} = execute_tool(ListAccounts, nil, %{"query" => "Acme"})

    assert Enum.map(accounts, & &1.name) == ["Acme"]
  end
end
