defmodule Atlas.MCP.Tools.GetEventTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.GetEvent

  test "returns the event body" do
    account = insert_account!(%{account_key: "event-body"})
    event = insert_event!(account, %{title: "Email", body: "Hello"})

    {:ok, payload} = execute_tool(GetEvent, nil, %{"event_id" => event.id})

    assert payload.title == "Email"
    assert payload.body == "Hello"
  end

  test "errors when the event is missing" do
    assert {:error, _} = execute_tool(GetEvent, nil, %{"event_id" => Ecto.UUID.generate()})
  end
end
