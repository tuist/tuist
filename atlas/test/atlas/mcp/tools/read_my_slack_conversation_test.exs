defmodule Atlas.MCP.Tools.ReadMySlackConversationTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Connections.Connection
  alias Atlas.MCP.Tools.ReadMySlackConversation

  @scopes ~w(search:read chat:write channels:history groups:history im:history mpim:history files:read)

  test "a reply's permalink reads its whole thread with the caller's token" do
    user = insert_user!()
    insert_slack!(insert_user!(), "xoxp-other", @scopes)
    insert_slack!(user, "xoxp-own", @scopes)

    http(fn conn ->
      assert conn.request_path == "/api/conversations.replies"
      assert ["Bearer xoxp-own"] = Plug.Conn.get_req_header(conn, "authorization")
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["channel"] == "C0123ABCD"
      # The thread parent from `thread_ts`, not the reply's own timestamp.
      assert conn.query_params["ts"] == "1762229900.000100"
      assert conn.query_params["limit"] == "200"

      Req.Test.json(conn, %{
        "ok" => true,
        "messages" => [
          %{"user" => "U1", "text" => "Here is our DPA", "ts" => "1762229900.000100", "reply_count" => 1},
          %{
            "user" => "U2",
            "text" => "",
            "ts" => "1762230000.000200",
            "thread_ts" => "1762229900.000100",
            # Slack Connect may withhold metadata until files.info is called.
            "files" => [%{"id" => "F0DPA", "file_access" => "check_file_info"}]
          }
        ],
        "response_metadata" => %{"next_cursor" => "bmV4dA=="}
      })
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:ok, result} =
             execute_tool(ReadMySlackConversation, conn, %{
               "permalink" =>
                 "https://tuist.slack.com/archives/C0123ABCD/p1762230000000200?thread_ts=1762229900.000100&cid=C0123ABCD",
               "limit" => 500
             })

    assert result.channel_id == "C0123ABCD"
    assert result.thread_timestamp == "1762229900.000100"
    assert result.next_cursor == "bmV4dA=="

    assert [%{reply_count: 1, files: []}, %{user: "U2", files: [%{id: "F0DPA", name: nil, size: nil}]}] =
             result.messages
  end

  test "a top-level permalink reads the message's own thread, and channel_id alone reads history" do
    user = insert_user!()
    insert_slack!(user, "xoxp-own", @scopes)
    test = self()

    http(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test, {conn.request_path, conn.query_params})
      Req.Test.json(conn, %{"ok" => true, "messages" => []})
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:ok, %{messages: [], next_cursor: nil}} =
             execute_tool(ReadMySlackConversation, conn, %{
               "permalink" => "https://tuist.slack.com/archives/C0123ABCD/p1762230000000200"
             })

    assert_received {"/api/conversations.replies", %{"ts" => "1762230000.000200"}}

    assert {:ok, %{thread_timestamp: nil}} =
             execute_tool(ReadMySlackConversation, conn, %{"channel_id" => "D1", "cursor" => "abc"})

    assert_received {"/api/conversations.history", %{"channel" => "D1", "cursor" => "abc", "limit" => "50"} = params}
    refute Map.has_key?(params, "ts")
  end

  test "a connection made before history scopes asks to reconnect without calling Slack" do
    user = insert_user!()
    insert_slack!(user, "xoxp-own", ["search:read", "chat:write"])
    stub(Req, :request, fn _ -> flunk("must not reach Slack") end)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:error, message} = ReadMySlackConversation.execute(conn, %{"channel_id" => "C1"})
    assert message =~ "Reconnect Slack"
  end

  test "rejects links that are not Slack message permalinks and shared Slack identities" do
    user = insert_user!()
    stub(Req, :request, fn _ -> flunk("must not reach Slack") end)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:error, "permalink must be" <> _} =
             ReadMySlackConversation.execute(conn, %{
               "permalink" => "https://evil.example/archives/C1/p1762230000000200"
             })

    assert {:error, "channel_id or permalink is required."} = ReadMySlackConversation.execute(conn, %{})

    slack = %{assigns: %{current_user: user, audit_interface: "slack"}}

    assert {:error, "Personal Slack reads are unavailable" <> _} =
             ReadMySlackConversation.execute(slack, %{"channel_id" => "C1"})
  end

  defp insert_slack!(user, token, scopes) do
    %Connection{user_id: user.id, provider: "slack"}
    |> Connection.changeset(%{
      provider_user_id: "U#{user.id}",
      account_name: "slack-user",
      workspace_id: "T1",
      access_token: token,
      scopes: scopes
    })
    |> Repo.insert!()
  end

  defp http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
