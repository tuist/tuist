defmodule Atlas.MCP.Tools.SendEmailBroadcastTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.SendEmailBroadcast

  test "queues a broadcast for an audience" do
    user = insert_user!()
    {:ok, audience} = GTM.create_email_audience(%{name: "MCP Digest"})
    {:ok, subscriber} = GTM.create_email_subscriber(%{email: "agent-reader@example.com", source: "test"})
    {:ok, _membership} = GTM.add_email_audience_subscriber(audience, subscriber)

    assert {:ok, %{broadcast: %{subject: "Agent update", recipients_count: 1, status: "pending"}}} =
             execute_tool(SendEmailBroadcast, conn_for(user), %{
               "audience_id" => audience.id,
               "subject" => "Agent update",
               "body_markdown" => "A useful update."
             })
  end
end
