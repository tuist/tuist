defmodule Atlas.MCP.Tools.ListAccountContactsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.ListAccountContacts

  test "returns contacts ordered by name" do
    account = insert_account!(%{account_key: "contacts-acct"})
    insert_contact!(account, %{full_name: "Zoe", email: "zoe@x.com"})
    insert_contact!(account, %{full_name: "Alice", email: "alice@x.com"})

    {:ok, %{contacts: contacts}} =
      execute_tool(ListAccountContacts, nil, %{"account_id" => account.id})

    assert Enum.map(contacts, & &1.full_name) == ["Alice", "Zoe"]
  end
end
