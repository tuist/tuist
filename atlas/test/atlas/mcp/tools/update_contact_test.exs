defmodule Atlas.MCP.Tools.UpdateContactTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Contact
  alias Atlas.MCP.Tools.UpdateContact

  test "updates an existing contact's title" do
    account = insert_account!(%{})
    contact = insert_contact!(account, %{full_name: "Bob", email: "bob@acme.io"})

    {:ok, payload} = execute_tool(UpdateContact, nil, %{"contact_id" => contact.id, "title" => "CTO"})

    assert payload.title == "CTO"
    assert Repo.get!(Contact, contact.id).title == "CTO"
  end

  test "errors when contact_id is missing" do
    assert {:error, _} = execute_tool(UpdateContact, nil, %{"title" => "x"})
  end

  test "errors when the contact is missing" do
    assert {:error, _} =
             execute_tool(UpdateContact, nil, %{
               "contact_id" => Ecto.UUID.generate(),
               "title" => "x"
             })
  end
end
