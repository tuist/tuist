defmodule Atlas.MCP.Tools.SyncMySocialPostsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.GTM.SocialPosts
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.SyncMySocialPosts

  test "the shared Slack agent cannot discover or run a person's billed X sync" do
    user = insert_user!()
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)
    stub(Proxy, :call_hoisted_tool, fn _, _, _ -> :not_proxy_tool end)
    stub(SocialPosts, :sync_x, fn _, _ -> flunk("shared identities must not reach X") end)

    for conn <- [
          %{assigns: %{current_user: user, audit_interface: "slack"}},
          %{assigns: %{current_user: user, mcp_claims: %{"slack_agent" => true}}}
        ] do
      listed = Server.handle_message(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      refute "sync_my_social_posts" in Enum.map(listed["result"]["tools"], & &1["name"])

      called =
        Server.handle_message(conn, %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{"name" => "sync_my_social_posts", "arguments" => %{}}
        })

      assert called["error"]["message"] =~ "not available"
      assert {:error, _} = SyncMySocialPosts.execute(conn, %{})
    end
  end

  test "a person can run the billed X sync a few times an hour, not in a loop" do
    user = insert_user!()
    other = insert_user!()
    test = self()

    stub(SocialPosts, :sync_x, fn synced, "mcp" ->
      send(test, {:synced, synced.id})
      {:ok, 7}
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    for _ <- 1..3, do: assert({:ok, %{posts: 7}} = execute_tool(SyncMySocialPosts, conn, %{}))
    assert {:error, message} = SyncMySocialPosts.execute(conn, %{})
    assert message =~ "rate"

    assert_received {:synced, id} when id == user.id
    assert_received {:synced, _}
    assert_received {:synced, _}
    refute_received {:synced, _}

    # The limit is per person.
    other_conn = %{assigns: %{current_user: other, audit_interface: "mcp"}}
    assert {:ok, %{posts: 7}} = execute_tool(SyncMySocialPosts, other_conn, %{})
  end
end
