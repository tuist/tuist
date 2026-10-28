defmodule Atlas.MCP.Tools.UpdateAccountTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Account
  alias Atlas.MCP.Tools.UpdateAccount
  alias Atlas.Repo

  test "updates editable fields and ignores tenancy-defining fields" do
    parent = insert_account!(%{name: "Parent"})
    account = insert_account!(%{name: "Old", segment: :lead})

    {:ok, payload} =
      execute_tool(UpdateAccount, nil, %{
        "account_id" => account.id,
        "name" => "New",
        "segment" => "customer",
        "hosting" => "self_hosted",
        "parent_account_id" => parent.id,
        "account_key" => "should-be-ignored"
      })

    assert payload.account.name == "New"
    assert payload.account.segment == :customer
    assert payload.account.hosting == "self_hosted"
    assert payload.account.parent_account_id == parent.id
    assert Repo.get!(Account, account.id).account_key == account.account_key
    assert Repo.get!(Account, account.id).hosting == "self_hosted"
  end

  test "returns a validation error for an invalid status" do
    account = insert_account!(%{})

    assert {:error, message} =
             execute_tool(UpdateAccount, nil, %{"account_id" => account.id, "status" => "on-fire"})

    assert message =~ "status"
  end

  test "returns an error for an unknown identifier" do
    assert {:error, _} = execute_tool(UpdateAccount, nil, %{"account_key" => "missing"})
  end
end
