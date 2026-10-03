defmodule Atlas.MCP.Tools.CreateEmailSubscriberTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.CreateEmailSubscriber

  test "creates a subscriber attributed to the current user" do
    user = insert_user!()

    assert {:ok, %{subscriber: %{id: id, email: "reader@example.com"}}} =
             execute_tool(CreateEmailSubscriber, conn_for(user), %{
               "email" => "Reader@Example.com",
               "first_name" => "Riley",
               "source" => "conference"
             })

    assert GTM.get_email_subscriber(id).first_name == "Riley"
  end
end
