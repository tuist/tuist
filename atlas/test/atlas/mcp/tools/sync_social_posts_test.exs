defmodule Atlas.MCP.Tools.SyncSocialPostsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialPosts
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.SyncSocialPosts

  setup do
    n = System.unique_integer([:positive])

    account =
      %SocialAccount{platform: "x", external_id: "acct#{n}"}
      |> SocialAccount.changeset(%{handle: "@brand#{n}", kind: "brand", access_token: "x-access"})
      |> Repo.insert!()

    %{account: account}
  end

  test "the shared Slack agent cannot discover or run the billed X sync" do
    user = insert_user!(%{scopes: ["gtm:write"]})
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)
    stub(Proxy, :call_hoisted_tool, fn _, _, _ -> :not_proxy_tool end)
    stub(SocialPosts, :sync_account, fn _, _ -> flunk("shared identities must not reach X") end)

    for conn <- [
          %{assigns: %{current_user: user, audit_interface: "slack"}},
          %{assigns: %{current_user: user, mcp_claims: %{"slack_agent" => true}}}
        ] do
      listed = Server.handle_message(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      refute "sync_social_posts" in Enum.map(listed["result"]["tools"], & &1["name"])

      called =
        Server.handle_message(conn, %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{"name" => "sync_social_posts", "arguments" => %{}}
        })

      assert called["error"]["message"] =~ "not available"
      assert {:error, _} = SyncSocialPosts.execute(conn, %{})
    end
  end

  test "syncing needs gtm:write" do
    stub(SocialPosts, :sync_account, fn _, _ -> flunk("readers must not reach X") end)
    conn = %{assigns: %{current_user: insert_user!(%{scopes: ["gtm:read"]}), audit_interface: "mcp"}}

    assert {:error, message} = SyncSocialPosts.execute(conn, %{})
    assert message =~ "gtm:write"
  end

  test "the billed X sync runs a few times an hour across everyone, not in a loop", %{account: account} do
    test = self()

    stub(SocialPosts, :sync_account, fn synced, opts ->
      send(test, {:synced, synced.id, opts[:actor].id})
      {:ok, 7}
    end)

    [first, second] = for _ <- 1..2, do: insert_user!(%{scopes: ["gtm:write"]})
    conn = fn user -> %{assigns: %{current_user: user, audit_interface: "mcp"}} end
    args = %{"account" => account.handle}

    for user <- [first, first, second] do
      assert {:ok, %{accounts: [%{posts: 7, kind: "brand"}]}} = execute_tool(SyncSocialPosts, conn.(user), args)
    end

    # The limit is shared: the accounts belong to Atlas, so another person cannot add runs.
    other = insert_user!(%{scopes: ["gtm:write"]})
    assert {:error, message} = SyncSocialPosts.execute(conn.(other), args)
    assert message =~ "rate"

    account_id = account.id
    first_id = first.id
    assert_received {:synced, ^account_id, ^first_id}
    assert_received {:synced, ^account_id, _}
    assert_received {:synced, ^account_id, _}
    refute_received {:synced, _, _}
  end

  test "an unknown handle is reported instead of syncing everything" do
    conn = %{assigns: %{current_user: insert_user!(%{scopes: ["gtm:write"]}), audit_interface: "mcp"}}
    assert {:error, message} = SyncSocialPosts.execute(conn, %{"account" => "@nobody"})
    assert message =~ "@nobody"
  end
end
