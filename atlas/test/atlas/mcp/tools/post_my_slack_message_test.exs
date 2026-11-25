defmodule Atlas.MCP.Tools.PostMySlackMessageTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Connection
  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.ToolApproval
  alias Atlas.MCP.Tools.PostMySlackMessage
  alias Atlas.Moodboard.SafeHTTP

  @scopes ~w(search:read chat:write channels:history groups:history im:history mpim:history files:read files:write)
  @redline "PK redlined contract bytes"

  test "posts a thread reply with a file as the caller only after they approve that exact call, once" do
    user = insert_user!()
    insert_slack!(insert_user!(), "xoxp-other", @scopes)
    insert_slack!(user, "xoxp-own", @scopes)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    args = %{
      "channel_id" => "D0123ABCD",
      "thread_timestamp" => "1762229900.000100",
      "text" => "Hi, our redlines are attached.",
      "files" => [%{"filename" => "dpa.docx", "title" => "DPA redlines", "content_base64" => Base.encode64(@redline)}]
    }

    stub(Req, :request, fn _ -> flunk("Slack must not be called before approval") end)
    assert {:error, message} = execute_tool(PostMySlackMessage, conn, args)
    assert message =~ "/approvals/"

    approval = Repo.get_by!(ToolApproval, user_id: user.id, server_name: "slack", tool_name: "post-message")

    # The person reviews the target, text and the file's exact bytes, not the base64 it came in.
    assert approval.arguments == %{
             "channel_id" => "D0123ABCD",
             "thread_timestamp" => "1762229900.000100",
             "text" => "Hi, our redlines are attached.",
             "files" => [
               %{
                 "filename" => "dpa.docx",
                 "title" => "DPA redlines",
                 "byte_size" => byte_size(@redline),
                 "sha256" => :sha256 |> :crypto.hash(@redline) |> Base.encode16(case: :lower)
               }
             ]
           }

    requested = Repo.get_by!(Activity, action: "mcp_tool_approval.requested", target_id: approval.id)
    refute Map.has_key?(requested.metadata["arguments"], "text")

    assert {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")

    # Different file bytes are a different call, so the approval does not cover them.
    other_bytes = put_in(args, ["files", Access.at(0), "content_base64"], Base.encode64("other"))
    assert {:error, "Posting to Slack" <> _} = execute_tool(PostMySlackMessage, conn, other_bytes)

    test = self()

    http(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/files.getUploadURLExternal" ->
          assert ["Bearer xoxp-own"] = Plug.Conn.get_req_header(conn, "authorization")
          assert URI.decode_query(body) == %{"filename" => "dpa.docx", "length" => "#{byte_size(@redline)}"}

          Req.Test.json(conn, %{
            "ok" => true,
            "upload_url" => "https://files.slack.com/upload/v1/abc",
            "file_id" => "F1"
          })

        "/upload/v1/abc" ->
          # The pre-signed upload URL gets the bytes but never the token.
          assert Plug.Conn.get_req_header(conn, "authorization") == []
          send(test, {:uploaded, body})
          Plug.Conn.send_resp(conn, 200, "OK - #{byte_size(body)}")

        "/api/files.completeUploadExternal" ->
          assert ["Bearer xoxp-own"] = Plug.Conn.get_req_header(conn, "authorization")
          form = URI.decode_query(body)
          assert form["channel_id"] == "D0123ABCD"
          assert form["thread_ts"] == "1762229900.000100"
          assert form["initial_comment"] == "Hi, our redlines are attached."
          assert Jason.decode!(form["files"]) == [%{"id" => "F1", "title" => "DPA redlines"}]

          Req.Test.json(conn, %{
            "ok" => true,
            "files" => [
              %{
                "id" => "F1",
                "title" => "DPA redlines",
                "permalink" => "https://tuist.slack.com/files/U1/F1/dpa.docx",
                "shares" => %{"private" => %{"D0123ABCD" => [%{"ts" => "1762230000.000200"}]}}
              }
            ]
          })
      end
    end)

    assert {:ok, result} = execute_tool(PostMySlackMessage, conn, args)
    assert_received {:uploaded, @redline}

    assert result == %{
             channel_id: "D0123ABCD",
             message_timestamp: "1762230000.000200",
             thread_timestamp: "1762229900.000100",
             files: [%{id: "F1", title: "DPA redlines", permalink: "https://tuist.slack.com/files/U1/F1/dpa.docx"}]
           }

    posted = Repo.get_by!(Activity, action: "connection.slack_message_posted", actor_id: user.id)
    assert posted.metadata["channel_id"] == "D0123ABCD"
    assert posted.metadata["message_timestamp"] == "1762230000.000200"
    assert posted.metadata["file_ids"] == ["F1"]
    refute inspect(posted.metadata) =~ "redlines are attached"

    # The approval is spent: repeating the call files a new request instead of posting twice.
    stub(Req, :request, fn _ -> flunk("a spent approval must not post again") end)
    assert {:error, "Posting to Slack" <> _} = execute_tool(PostMySlackMessage, conn, args)
  end

  test "posts text alone with chat.postMessage, broadcasting a thread reply when asked" do
    user = insert_user!()
    insert_slack!(user, "xoxp-own", ["chat:write"])
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    args = %{
      "channel_id" => "C0456EFGH",
      "thread_timestamp" => "1762229900.000100",
      "reply_broadcast" => true,
      "text" => "Shipped."
    }

    approve!(conn, user, args)

    http(fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "channel" => "C0456EFGH",
               "text" => "Shipped.",
               "thread_ts" => "1762229900.000100",
               "reply_broadcast" => true
             }

      Req.Test.json(conn, %{"ok" => true, "channel" => "C0456EFGH", "ts" => "1762230000.000300"})
    end)

    assert {:ok, %{message_timestamp: "1762230000.000300", files: []}} =
             execute_tool(PostMySlackMessage, conn, args)
  end

  test "approves a file fetched from a url by its bytes and reports Slack's refusal by code" do
    user = insert_user!()
    insert_slack!(user, "xoxp-own", @scopes)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    url = "https://ampcode.com/files/tmp/redline.docx?token=secret"

    expect(SafeHTTP, :fetch, 2, fn ^url, opts ->
      assert opts[:media_bodies]
      {:ok, %{status: 200, headers: [], body: @redline, url: url}}
    end)

    args = %{"channel_id" => "C0456EFGH", "files" => [%{"filename" => "redline.docx", "url" => url}]}
    approve!(conn, user, args)

    approval = Repo.get_by!(ToolApproval, user_id: user.id, server_name: "slack")
    assert [%{"byte_size" => 26, "filename" => "redline.docx"}] = approval.arguments["files"]
    refute inspect(approval.arguments) =~ "secret"

    http(fn conn -> Req.Test.json(conn, %{"ok" => false, "error" => "is_archived"}) end)

    assert {:error, "Slack refused the request (is_archived)."} = execute_tool(PostMySlackMessage, conn, args)
  end

  test "refuses shared identities, other interfaces, invalid combinations and missing scopes without filing approvals" do
    user = insert_user!()
    insert_slack!(user, "xoxp-own", ~w(search:read chat:write))
    stub(Req, :request, fn _ -> flunk("must not reach Slack") end)
    args = %{"channel_id" => "C1", "text" => "hi"}

    assert {:error, "Posting to Slack as a person is unavailable" <> _} =
             PostMySlackMessage.execute(%{assigns: %{current_user: user, audit_interface: "slack"}}, args)

    assert {:error, "Posting to Slack as a person needs their approval and is only callable over Atlas MCP."} =
             PostMySlackMessage.execute(%{assigns: %{current_user: user, audit_interface: "api"}}, args)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    assert {:error, "Pass text, files or both."} = PostMySlackMessage.execute(conn, %{"channel_id" => "C1"})

    assert {:error, "reply_broadcast needs thread_timestamp."} =
             PostMySlackMessage.execute(conn, Map.put(args, "reply_broadcast", true))

    assert {:error, "Slack cannot broadcast" <> _} =
             PostMySlackMessage.execute(conn, %{
               "channel_id" => "C1",
               "thread_timestamp" => "1.2",
               "reply_broadcast" => true,
               "files" => [%{"filename" => "a.txt", "content_base64" => Base.encode64("a")}]
             })

    # Uploading needs files:write, which older connections lack.
    assert {:error, message} =
             PostMySlackMessage.execute(
               conn,
               Map.put(args, "files", [%{"filename" => "a.txt", "content_base64" => Base.encode64("a")}])
             )

    assert message =~ "Reconnect Slack"
    assert Repo.aggregate(ToolApproval, :count) == 0
  end

  test "the MCP audit trail keeps the target but not the text or files" do
    user = insert_user!()
    stub(Proxy, :call_hoisted_tool, fn _, _, _ -> :not_proxy_tool end)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    Server.handle_message(conn, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "post_my_slack_message",
        "arguments" => %{
          "channel_id" => "C1",
          "text" => "confidential",
          "files" => [%{"filename" => "a.txt", "content_base64" => Base.encode64("a")}]
        }
      }
    })

    activity = Repo.get_by!(Activity, action: "mcp.tool_called", actor_id: user.id)
    assert activity.metadata["arguments"] == %{"channel_id" => "C1", "file_count" => 1}
  end

  defp approve!(conn, user, args) do
    assert {:error, "Posting to Slack" <> _} = execute_tool(PostMySlackMessage, conn, args)
    approval = Repo.get_by!(ToolApproval, user_id: user.id, server_name: "slack", status: "pending")
    assert {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")
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
