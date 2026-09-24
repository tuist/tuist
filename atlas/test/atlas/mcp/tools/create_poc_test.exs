defmodule Atlas.MCP.Tools.CreatePOCTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreatePOC

  test "creates a POC via MCP" do
    user = insert_user!()
    account = insert_account!()

    assert {:ok, %{"poc" => poc}} =
             execute_tool(CreatePOC, conn_for(user), %{
               "account_id" => account.id,
               "title" => "Enterprise evaluation",
               "hosting" => "self_hosted"
             })

    assert poc["account_id"] == account.id
    assert poc["title"] == "Enterprise evaluation"
    assert poc["hosting"] == "self_hosted"
    assert poc["status"] == "draft"
    assert is_nil(poc["public_token"])
    assert poc["dashboard_path"] == "/commercial/sales/pocs/#{poc["id"]}"
  end

  test "rejects an unauthenticated caller" do
    account = insert_account!()

    assert {:error, _} =
             execute_tool(CreatePOC, conn_for(nil), %{
               "account_id" => account.id,
               "title" => "Nope"
             })
  end

  test "reports validation errors when the account is unknown" do
    user = insert_user!()

    assert {:error, message} =
             execute_tool(CreatePOC, conn_for(user), %{
               "account_id" => Ecto.UUID.generate(),
               "title" => "Ghost"
             })

    assert message =~ "account"
  end
end
