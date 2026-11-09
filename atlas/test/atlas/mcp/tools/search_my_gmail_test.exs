defmodule Atlas.MCP.Tools.SearchMyGmailTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Connections.Config
  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.CreateMyGmailDraft
  alias Atlas.MCP.Tools.GetMyGmailDraft
  alias Atlas.MCP.Tools.GetMyGmailMessage
  alias Atlas.MCP.Tools.SearchMyGmail
  alias Atlas.MCP.Tools.SearchMySlack
  alias Atlas.MCP.Tools.SendMyGmailDraft
  alias Atlas.MCP.Tools.UpdateMyGmailDraft
  alias Atlas.Orbit.ToolPolicy

  test "personal mailbox and Slack tools are MCP-only, never Orbit or Automation capabilities" do
    for {module, name} <- [
          {SearchMyGmail, "search_my_gmail"},
          {GetMyGmailMessage, "get_my_gmail_message"},
          {GetMyGmailDraft, "get_my_gmail_draft"},
          {CreateMyGmailDraft, "create_my_gmail_draft"},
          {UpdateMyGmailDraft, "update_my_gmail_draft"},
          {SendMyGmailDraft, "send_my_gmail_draft"},
          {SearchMySlack, "search_my_slack"}
        ] do
      assert module in Server.tool_modules()
      assert name in ToolPolicy.never()
      assert Map.has_key?(DomainRegistry.exclusions(), name)
    end
  end

  test "shared Slack identities cannot list or run personal mailbox tools" do
    user = insert_user!()
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)
    stub(Req, :request, fn _ -> flunk("shared identities must not reach Gmail") end)
    conn = %{assigns: %{current_user: user, audit_interface: "slack"}}

    response = Server.handle_message(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    names = Enum.map(response["result"]["tools"], & &1["name"])
    refute "search_my_gmail" in names
    refute "search_my_slack" in names
    assert {:error, _} = SearchMyGmail.execute(conn, %{"query" => "in:inbox"})
  end

  test "searches with the caller's own token and returns message metadata" do
    user = insert_user!()
    other = insert_user!()
    insert_google!(user, "own-token", [Gmail.scope()])
    insert_google!(other, "other-token", [Gmail.scope()])

    http(fn conn ->
      assert ["Bearer own-token"] = Plug.Conn.get_req_header(conn, "authorization")
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/gmail/v1/users/me/messages" ->
          assert conn.query_params["q"] == "from:alice"
          assert conn.query_params["maxResults"] == "25"
          Req.Test.json(conn, %{"messages" => [%{"id" => "m1"}, %{"id" => "gone"}]})

        "/gmail/v1/users/me/messages/m1" ->
          Req.Test.json(conn, %{
            "id" => "m1",
            "threadId" => "t1",
            "snippet" => "Renewal next week",
            "labelIds" => ["INBOX"],
            "payload" => %{
              "headers" => [
                %{"name" => "from", "value" => "Alice <alice@example.com>"},
                %{"name" => "Subject", "value" => "Renewal"}
              ]
            }
          })

        "/gmail/v1/users/me/messages/gone" ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:ok, %{messages: [message]}} =
             execute_tool(SearchMyGmail, conn, %{"query" => "from:alice", "limit" => 500})

    assert message.from == "Alice <alice@example.com>"
    assert message.subject == "Renewal"
    assert message.to == ""
    assert message.thread_id == "t1"

    activity = Repo.get_by!(Activity, action: "connection.gmail_searched", actor_id: user.id)
    assert activity.metadata["count"] == 1
    refute JSON.encode!(activity.metadata) =~ "alice"
  end

  test "the MCP audit trail never keeps the mailbox query" do
    user = insert_user!()
    stub(Proxy, :call_hoisted_tool, fn _, _, _ -> :not_proxy_tool end)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    Server.handle_message(conn, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "search_my_gmail", "arguments" => %{"query" => "from:lawyer"}}
    })

    activity = Repo.get_by!(Activity, action: "mcp.tool_called", actor_id: user.id)
    assert activity.metadata["arguments"] == %{}
  end

  test "asks for Gmail consent before calling Google when only the base grant exists" do
    user = insert_user!()
    insert_google!(user, "own-token", ["openid", "email"])
    stub(Req, :request, fn _ -> flunk("Gmail must not be called without gmail.readonly") end)
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

    assert {:error, message} = SearchMyGmail.execute(conn, %{"query" => "in:inbox"})
    assert message =~ "Grant Gmail access"
    assert message =~ "/settings/connections"

    assert {:error, message} = SearchMyGmail.execute(%{assigns: %{current_user: insert_user!()}}, %{"query" => "x"})
    assert message =~ "Connect your Gmail account"
  end

  test "a disabled Gmail API is reported as such, not as an expired connection" do
    user = insert_user!()
    google = insert_google!(user, "own-token", [Gmail.scope()])
    stub(Config, :credentials, fn _ -> flunk("a 403 must not trigger a token refresh") end)

    http(fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{
        "error" => %{
          "code" => 403,
          "message" => "Gmail API has not been used in project 433472508422 before or it is disabled.",
          "errors" => [%{"reason" => "accessNotConfigured"}],
          "status" => "PERMISSION_DENIED",
          "details" => [%{"@type" => "type.googleapis.com/google.rpc.ErrorInfo", "reason" => "SERVICE_DISABLED"}]
        }
      })
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    assert {:error, message} = SearchMyGmail.execute(conn, %{"query" => "in:inbox"})
    assert message =~ "Gmail API is not enabled"
    refute message =~ "expired"
    refute Repo.reload!(google).needs_authorization

    activity = Repo.get_by!(Activity, action: "connection.gmail_failed", actor_id: user.id)
    assert %{"operation" => "search", "status" => 403, "reason" => "SERVICE_DISABLED"} = activity.metadata
    refute JSON.encode!(activity.metadata) =~ "433472508422"
  end

  test "a Workspace or permission 403 says reconnecting will not help" do
    user = insert_user!()
    insert_google!(user, "own-token", [Gmail.scope()])

    http(fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{
        "error" => %{"code" => 403, "errors" => [%{"reason" => "forbidden"}], "status" => "PERMISSION_DENIED"}
      })
    end)

    assert {:error, message} = SearchMyGmail.execute(%{assigns: %{current_user: user}}, %{"query" => "x"})
    assert message =~ "HTTP 403 forbidden"
    assert message =~ "reconnecting will not help"
  end

  test "a 401 refreshes the token once and retries, then reports a rejection that survives the refresh" do
    user = insert_user!()
    google = insert_google!(user, "stale-token", [Gmail.scope()])
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    Process.put(:accepted, "fresh-token")

    http(fn conn ->
      case conn.request_path do
        "/token" ->
          send(self(), :refreshed)
          Req.Test.json(conn, %{"access_token" => "fresh-token", "expires_in" => 3600})

        "/gmail/v1/users/me/messages" ->
          if Plug.Conn.get_req_header(conn, "authorization") == ["Bearer #{Process.get(:accepted)}"],
            do: Req.Test.json(conn, %{"messages" => []}),
            else: conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{"status" => "UNAUTHENTICATED"}})
      end
    end)

    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    assert {:ok, %{messages: []}} = SearchMyGmail.execute(conn, %{"query" => "x"})
    assert_received :refreshed
    assert Repo.reload!(google).access_token == "fresh-token"

    # A token Google rejects even right after a refresh is refreshed only once.
    Process.put(:accepted, "never")
    assert {:error, message} = SearchMyGmail.execute(conn, %{"query" => "x"})
    assert message =~ "even after refreshing"
    assert_received :refreshed
    refute_received :refreshed
  end

  test "a 401 whose refresh Google refuses marks the connection for reconnecting" do
    user = insert_user!()
    google = insert_google!(user, "stale-token", [Gmail.scope()])
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)

    http(fn conn ->
      case conn.request_path do
        "/token" -> conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
        _ -> conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{"status" => "UNAUTHENTICATED"}})
      end
    end)

    assert {:error, message} = SearchMyGmail.execute(%{assigns: %{current_user: user}}, %{"query" => "x"})
    assert message =~ "connection expired"
    assert Repo.reload!(google).needs_authorization
  end

  defp insert_google!(user, token, scopes) do
    %Connection{user_id: user.id, provider: "google"}
    |> Connection.changeset(%{
      provider_user_id: "google-#{user.id}",
      account_name: user.email,
      access_token: token,
      refresh_token: "refresh",
      scopes: scopes
    })
    |> Repo.insert!()
  end

  defp http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
