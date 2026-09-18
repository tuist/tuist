defmodule Atlas.MCP.Tools.GetPostmortemTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tools.GetPostmortem

  test "fetches a postmortem by public number" do
    user = insert_user!()
    {:ok, postmortem} = Postmortems.publish_postmortem(%{"body" => "# a\n\nbb"}, user)

    assert {:ok, %{"postmortem" => payload}} =
             execute_tool(GetPostmortem, conn_for(user), %{
               "id" => to_string(postmortem.number)
             })

    assert payload["id"] == postmortem.id
  end

  test "returns not_found for a missing reference" do
    assert {:error, "Postmortem not found."} =
             execute_tool(GetPostmortem, conn_for(nil), %{"id" => "999999"})
  end
end
