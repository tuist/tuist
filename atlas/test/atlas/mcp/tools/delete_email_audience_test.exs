defmodule Atlas.MCP.Tools.DeleteEmailAudienceTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.DeleteEmailAudience

  test "deletes an unused manual audience" do
    name = "Disposable audience #{System.unique_integer([:positive])}"
    {:ok, audience} = GTM.create_email_audience(%{"name" => name})

    assert {:ok, payload} =
             execute_tool(DeleteEmailAudience, conn_for(nil), %{"audience_id" => audience.id})

    assert %{deleted: true, audience: %{id: id}} = payload
    assert id == audience.id
    refute GTM.get_email_audience(audience.id)
  end

  test "does not delete a dynamic audience" do
    {:ok, audience} =
      GTM.create_email_audience(%{
        "name" => "Dynamic audience #{System.unique_integer([:positive])}",
        "membership_type" => "dynamic"
      })

    assert {:error, "Dynamic email audiences cannot be deleted."} =
             execute_tool(DeleteEmailAudience, conn_for(nil), %{"audience_id" => audience.id})

    assert GTM.get_email_audience(audience.id)
  end
end
