defmodule Atlas.MCP.Tools.PublishPOCTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tools.PublishPOC
  alias Atlas.MCP.Tools.UnpublishPOC

  test "publishing a POC returns a public URL and stays idempotent" do
    user = insert_user!()
    account = insert_account!()
    {:ok, poc} = POCs.create_poc(%{"account_id" => account.id, "title" => "Public"}, user)

    assert {:ok, %{"poc" => first}} = execute_tool(PublishPOC, conn_for(user), %{"id" => poc.id})
    assert is_binary(first["public_token"])
    assert first["public_url"] =~ "/p/pocs/#{first["public_token"]}"

    assert {:ok, %{"poc" => second}} = execute_tool(PublishPOC, conn_for(user), %{"id" => poc.id})
    assert second["public_token"] == first["public_token"]

    assert {:ok, %{"poc" => rotated}} =
             execute_tool(PublishPOC, conn_for(user), %{"id" => poc.id, "rotate" => true})

    assert rotated["public_token"] != first["public_token"]

    assert {:ok, %{"poc" => cleared}} =
             execute_tool(UnpublishPOC, conn_for(user), %{"id" => poc.id})

    assert is_nil(cleared["public_token"])
    assert is_nil(cleared["public_url"])
  end

  test "rejects unauthenticated callers" do
    user = insert_user!()
    account = insert_account!()
    {:ok, poc} = POCs.create_poc(%{"account_id" => account.id, "title" => "Public"}, user)

    assert {:error, _} = execute_tool(PublishPOC, conn_for(nil), %{"id" => poc.id})
  end
end
