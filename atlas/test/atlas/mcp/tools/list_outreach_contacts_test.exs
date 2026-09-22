defmodule Atlas.MCP.Tools.ListOutreachContactsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.ListOutreachContacts

  test "lists only contacts enrolled in outreach" do
    account = insert_account!(%{name: "Acme"})

    enrolled =
      insert_contact!(account, %{
        full_name: "Jordan Lee",
        outreach_enrolled_at: ~U[2026-07-01 09:00:00Z],
        outreach_status: "connected"
      })

    _regular_contact = insert_contact!(account, %{full_name: "Customer Contact"})

    assert {:ok, %{contacts: [contact], count: 1}} =
             execute_tool(ListOutreachContacts, nil, %{"status" => "connected"})

    assert contact.id == enrolled.id
    assert contact.account_name == "Acme"
  end
end
