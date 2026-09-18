defmodule Atlas.MCP.Tools.PagesStartDeployTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.MCP.Tools.PagesStartDeploy

  test "creates the page on first deploy and returns presigned uploads" do
    user = insert_user!()

    Atlas.ObjectStorage
    |> stub(:presigned_put_url, fn _key, _opts -> {:ok, "https://example.test/upload"} end)

    assert {:ok, %{"deploy_id" => deploy_id, "page" => page, "uploads" => uploads}} =
             execute_tool(PagesStartDeploy, conn_for(user), %{
               "slug" => "dashboards",
               "title" => "Team dashboards",
               "files" => [
                 %{"path" => "index.html", "size" => 12}
               ]
             })

    assert is_binary(deploy_id)
    assert page["slug"] == "dashboards"
    assert page["url"] =~ "dashboards"
    assert [%{"path" => "index.html", "upload_url" => "https://example.test/upload"}] = uploads
  end

  test "rejects an unauthenticated caller" do
    assert {:error, _reason} =
             execute_tool(PagesStartDeploy, conn_for(nil), %{
               "slug" => "public-site",
               "files" => [%{"path" => "index.html", "size" => 1}]
             })
  end

  test "rejects reserved slugs" do
    user = insert_user!()

    assert {:error, message} =
             execute_tool(PagesStartDeploy, conn_for(user), %{
               "slug" => "api",
               "files" => [%{"path" => "index.html", "size" => 1}]
             })

    assert message =~ "reserved" or message =~ "Invalid"
  end
end
