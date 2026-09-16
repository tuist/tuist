defmodule Atlas.MCP.Tools.MarkAccountNotAccountTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Account
  alias Atlas.MCP.Tools.MarkAccountNotAccount
  alias Atlas.Repo

  test "marks an account as not an account" do
    account = insert_account!(%{name: "Grafana Labs", primary_domain: "grafana.com"})

    assert {:ok, payload} =
             execute_tool(MarkAccountNotAccount, nil, %{
               "account_id" => account.id,
               "reason" => "Vendor"
             })

    assert payload.account.id == account.id
    assert payload.account.not_an_account_at
    assert payload.account.not_an_account_reason == "Vendor"

    stored = Repo.get!(Account, account.id)
    assert stored.not_an_account_at
    assert stored.not_an_account_reason == "Vendor"
  end

  test "returns an error for an unknown identifier" do
    assert {:error, _message} = execute_tool(MarkAccountNotAccount, nil, %{"account_key" => "missing"})
  end
end
