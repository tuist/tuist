defmodule Atlas.MCP.Tools.RecordOutreachEventTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Contact
  alias Atlas.MCP.Tools.RecordOutreachEvent

  test "records a message and advances the contact stage" do
    user = insert_user!()
    account = insert_account!(%{})
    contact = insert_contact!(account, %{outreach_enrolled_at: ~U[2026-07-01 09:00:00Z]})

    assert {:ok, payload} =
             execute_tool(RecordOutreachEvent, mcp_conn(user), %{
               "contact_id" => contact.id,
               "kind" => "message_sent",
               "body" => "What has been difficult about the build feedback loop?",
               "occurred_at" => "2026-07-03T11:00:00Z"
             })

    assert payload.outreach_status == "conversation_started"
    assert [%{kind: "message_sent", author_email: author_email}] = payload.events
    assert author_email == user.email
    assert Repo.get!(Contact, contact.id).outreach_status == "conversation_started"
  end

  test "classifies a received message outcome" do
    user = insert_user!()
    account = insert_account!(%{})
    contact = insert_contact!(account, %{outreach_enrolled_at: ~U[2026-07-01 09:00:00Z]})

    assert {:ok, _payload} =
             execute_tool(RecordOutreachEvent, mcp_conn(user), %{
               "contact_id" => contact.id,
               "kind" => "message_sent",
               "body" => "How is build feedback working for your team?",
               "occurred_at" => "2026-07-03T11:00:00Z"
             })

    assert {:ok, payload} =
             execute_tool(RecordOutreachEvent, mcp_conn(user), %{
               "contact_id" => contact.id,
               "kind" => "message_received",
               "body" => "It is timely. I would like to learn more.",
               "response_outcome" => "positive_reply",
               "occurred_at" => "2026-07-03T12:00:00Z"
             })

    assert payload.outreach_status == "interested"
    assert [%{response_outcome: "positive_reply"}, %{response_outcome: nil}] = payload.events
  end
end
