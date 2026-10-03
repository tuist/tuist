defmodule Atlas.MCP.Tools.ListAccountEventsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.ListAccountEvents

  test "returns events most recent first, filtered by kind" do
    account = insert_account!(%{account_key: "events-acct"})
    insert_event!(account, %{title: "Old", kind: "email", occurred_at: ~U[2025-01-01 00:00:00Z]})
    insert_event!(account, %{title: "New", kind: "email", occurred_at: ~U[2025-06-01 00:00:00Z]})
    insert_event!(account, %{title: "Meeting", kind: "meeting", occurred_at: ~U[2025-05-01 00:00:00Z]})

    {:ok, %{events: events}} =
      execute_tool(ListAccountEvents, nil, %{"account_id" => account.id, "kind" => "email"})

    assert Enum.map(events, & &1.title) == ["New", "Old"]
  end
end
