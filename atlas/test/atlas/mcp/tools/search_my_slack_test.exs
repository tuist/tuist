defmodule Atlas.MCP.Tools.SearchMySlackTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Connections.Connection
  alias Atlas.MCP.Tools.SearchMySlack

  test "searches with the caller's user token, newest first, and maps matches" do
    user = insert_user!()
    insert_slack!(insert_user!(), "xoxp-other")
    insert_slack!(user, "xoxp-own")

    http(fn conn ->
      assert ["Bearer xoxp-own"] = Plug.Conn.get_req_header(conn, "authorization")
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["query"] == "deploy in:#eng"
      assert conn.query_params["sort_dir"] == "desc"
      assert conn.query_params["count"] == "50"

      Req.Test.json(conn, %{
        "ok" => true,
        "messages" => %{
          "matches" => [
            %{
              "text" => "Deploy is done",
              "username" => "marek",
              "ts" => "1762230000.000100",
              "channel" => %{"id" => "C1", "name" => "eng"},
              "permalink" => "https://tuist.slack.com/archives/C1/p1762230000000100"
            }
          ]
        }
      })
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:ok, %{messages: [message]}} =
             execute_tool(SearchMySlack, conn, %{"query" => "deploy in:#eng", "limit" => 80})

    assert message.channel_name == "eng"
    assert message.user == "marek"
    assert message.thread_timestamp == nil
  end

  test "a revoked Slack token asks the caller to reconnect" do
    user = insert_user!()
    insert_slack!(user, "xoxp-own")
    http(fn conn -> Req.Test.json(conn, %{"ok" => false, "error" => "token_revoked"}) end)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:error, message} = SearchMySlack.execute(conn, %{"query" => "x"})
    assert message =~ "Reconnect"
  end

  defp insert_slack!(user, token) do
    %Connection{user_id: user.id, provider: "slack"}
    |> Connection.changeset(%{
      provider_user_id: "U#{user.id}",
      account_name: "slack-user",
      workspace_id: "T1",
      access_token: token,
      scopes: ["search:read", "chat:write"]
    })
    |> Repo.insert!()
  end

  defp http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
