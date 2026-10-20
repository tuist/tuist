defmodule Atlas.MCP.Tools.CreateAccountNoteTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreateAccountNote

  test "appends a note event attributed to the user" do
    account = insert_account!(%{})
    user = insert_user!()

    {:ok, payload} =
      execute_tool(CreateAccountNote, conn_for(user), %{
        "account_id" => account.id,
        "body" => "Spoke with Alice; renewal looks healthy."
      })

    assert payload.event.body =~ "renewal"
    assert payload.event.kind in ["note", "atlas_note"]
  end

  test "rejects an empty body" do
    account = insert_account!(%{})

    assert {:error, _} =
             execute_tool(CreateAccountNote, conn_for(nil), %{
               "account_id" => account.id,
               "body" => "  "
             })
  end
end
