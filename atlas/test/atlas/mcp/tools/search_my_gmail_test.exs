defmodule Atlas.MCP.Tools.SearchMyGmailTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.GetMyGmailMessage
  alias Atlas.MCP.Tools.SearchMyGmail
  alias Atlas.MCP.Tools.SearchMySlack
  alias Atlas.Orbit.ToolPolicy

  test "personal mailbox and Slack tools are MCP-only, never Orbit or Automation capabilities" do
    for {module, name} <- [
          {SearchMyGmail, "search_my_gmail"},
          {GetMyGmailMessage, "get_my_gmail_message"},
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
