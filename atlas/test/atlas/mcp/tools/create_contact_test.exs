defmodule Atlas.MCP.Tools.CreateContactTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Contact
  alias Atlas.MCP.Tools.CreateContact

  test "creates a contact for the account" do
    account = insert_account!(%{})

    {:ok, payload} =
      execute_tool(CreateContact, nil, %{
        "account_id" => account.id,
        "full_name" => "Bob",
        "email" => "bob@acme.io",
        "title" => "CTO"
      })

    assert payload.full_name == "Bob"
    assert payload.title == "CTO"

    contact = Repo.get!(Contact, payload.id)
    assert contact.account_id == account.id
  end

  test "creates a LinkedIn-only contact when email is unavailable" do
    account = insert_account!(%{})

    assert {:ok, payload} =
             execute_tool(CreateContact, nil, %{
               "account_id" => account.id,
               "full_name" => "Bob",
               "linkedin_url" => "https://www.linkedin.com/in/bob"
             })

    assert payload.email == nil
    assert payload.linkedin_url == "https://www.linkedin.com/in/bob"
  end

  test "returns a validation error when both email and LinkedIn are missing" do
    account = insert_account!(%{})

    assert {:error, _} =
             execute_tool(CreateContact, nil, %{"account_id" => account.id, "full_name" => "Bob"})
  end
end
