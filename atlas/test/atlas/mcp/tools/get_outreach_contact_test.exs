defmodule Atlas.MCP.Tools.GetOutreachContactTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Event
  alias Atlas.MCP.Tools.GetOutreachContact

  test "returns a contact with its outreach events" do
    account = insert_account!(%{name: "Acme"})
    contact = insert_contact!(account, %{outreach_enrolled_at: ~U[2026-07-01 09:00:00Z]})

    %Event{account_id: account.id, contact_id: contact.id}
    |> Event.changeset(%{
      external_id: "outreach-test-event",
      source: "linkedin",
      kind: "connection_requested",
      title: "Connection request sent",
      occurred_at: ~U[2026-07-02 10:00:00Z]
    })
    |> Repo.insert!()

    assert {:ok, payload} =
             execute_tool(GetOutreachContact, nil, %{"contact_id" => contact.id})

    assert payload.id == contact.id
    assert [%{kind: "connection_requested"}] = payload.events
  end
end
