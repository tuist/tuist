defmodule Atlas.MCP.Tools.MyGmailDraftsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.ToolApproval
  alias Atlas.MCP.Tools.CreateMyGmailDraft
  alias Atlas.MCP.Tools.GetMyGmailDraft
  alias Atlas.MCP.Tools.SendMyGmailDraft
  alias Atlas.MCP.Tools.UpdateMyGmailDraft

  test "a reply draft is plain text, threaded under the original and keeps its UTF-8 subject and body" do
    user = insert_google!([Gmail.scope(), Gmail.compose_scope()])

    gmail(fn
      "GET", "/gmail/v1/users/me/messages/orig", conn ->
        assert conn.query_params["format"] == "metadata"

        Req.Test.json(conn, %{
          "id" => "orig",
          "threadId" => "thread-1",
          "payload" => %{
            "headers" => [
              %{"name" => "Message-Id", "value" => "<orig@mail.example>"},
              %{"name" => "References", "value" => "<root@mail.example>"}
            ]
          }
        })

      "POST", "/gmail/v1/users/me/drafts", conn ->
        message = conn |> json_body() |> Map.fetch!("message")
        send(self(), {:created, message})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-1", "threadId" => "thread-1"}})
    end)

    args = %{
      "to" => ["anna@example.com", "ben@example.org"],
      "cc" => ["cleo@example.net"],
      "subject" => "Re: Vertrag für Käthe",
      "body" => "Hallo Käthe,\n\nanbei die Änderungen.",
      "reply_to_message_id" => "orig"
    }

    assert {:ok, %{draft: draft}} = execute_tool(CreateMyGmailDraft, agent_conn(user), args)
    assert draft.id == "draft-1"
    assert draft.thread_id == "thread-1"
    assert draft.in_reply_to == "<orig@mail.example>"

    assert_received {:created, %{"threadId" => "thread-1", "raw" => raw}}
    {headers, body} = parse(raw)
    assert headers["to"] == "anna@example.com, ben@example.org"
    assert headers["cc"] == "cleo@example.net"
    assert headers["in-reply-to"] == "<orig@mail.example>"
    assert headers["references"] == "<root@mail.example> <orig@mail.example>"
    assert headers["content-type"] == "text/plain; charset=UTF-8"
    refute Map.has_key?(headers, "bcc")
    assert decode_words(headers["subject"]) == "Re: Vertrag für Käthe"
    assert body == "Hallo Käthe,\n\nanbei die Änderungen."

    activity = Repo.get_by!(Activity, action: "connection.gmail_draft_created", actor_id: user.id)
    assert activity.metadata["draft_id"] == "draft-1"
    assert activity.metadata["reply"] == true
    refute JSON.encode!(activity.metadata) =~ ~r/anna|Käthe|Vertrag/
  end

  test "recipients and subjects cannot inject headers, and nothing reaches Gmail" do
    user = insert_google!([Gmail.compose_scope()])
    stub(Req, :request, fn _ -> flunk("invalid drafts must not reach Gmail") end)
    base = %{"to" => ["anna@example.com"], "subject" => "Hi", "body" => "Hello"}

    for args <- [
          %{base | "to" => ["anna@example.com\r\nBcc: eve@example.com"]},
          %{base | "to" => ["Anna <anna@example.com>"]},
          %{base | "subject" => "Hi\r\nBcc: eve@example.com"},
          Map.put(base, "cc", ["eve@example.com, mallory@example.com"]),
          %{base | "to" => []}
        ] do
      assert {:error, message} = CreateMyGmailDraft.execute(agent_conn(user), args)
      refute message =~ "expired"
    end
  end

  test "drafts need the separate drafts consent, read access alone is not enough" do
    user = insert_google!([Gmail.scope()])
    stub(Req, :request, fn _ -> flunk("Gmail must not be called without gmail.compose") end)

    assert {:error, message} =
             CreateMyGmailDraft.execute(agent_conn(user), %{"to" => ["a@example.com"], "subject" => "s", "body" => "b"})

    assert message =~ "Allow Gmail drafts"
  end

  test "an update without a reply id keeps the draft's thread and reply headers" do
    user = insert_google!([Gmail.compose_scope()])
    Process.put(:draft, draft_payload("Old subject", "Old body", in_reply_to: "<orig@mail.example>"))

    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        Req.Test.json(conn, Process.get(:draft))

      "PUT", "/gmail/v1/users/me/drafts/draft-1", conn ->
        body = json_body(conn)
        send(self(), {:updated, body})
        Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2", "threadId" => "thread-1"}})
    end)

    args = %{"draft_id" => "draft-1", "to" => ["anna@example.com"], "subject" => "Re: New", "body" => "New body"}

    assert {:ok, %{draft: %{in_reply_to: "<orig@mail.example>"}}} =
             execute_tool(UpdateMyGmailDraft, agent_conn(user), args)

    assert_received {:updated, %{"id" => "draft-1", "message" => %{"threadId" => "thread-1", "raw" => raw}}}
    {headers, body} = parse(raw)
    assert headers["in-reply-to"] == "<orig@mail.example>"
    assert headers["references"] == "<orig@mail.example>"
    assert headers["subject"] == "Re: New"
    assert body == "New body"
  end

  test "sending waits for the owner's approval of the exact draft, refuses a changed draft and sends once" do
    user = insert_google!([Gmail.compose_scope()])
    approved = draft_payload("Renewal", "Price is 10k")
    Process.put(:draft, approved)
    send_gmail()

    # The first call only files a request; nothing is sent.
    assert {:error, message} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    assert [%ToolApproval{id: id} = approval] = MCP.list_pending_tool_approvals(user, server_names: ["gmail"])
    assert message =~ "/settings/connections#gmail-approval-#{id}"
    refute message =~ "changed"
    refute_received :sent

    # Approval rows and their audit events hold no mail content.
    assert Map.keys(approval.arguments) == ["digest", "draft_id"]
    refute JSON.encode!(approval.arguments) =~ ~r/Renewal|10k|anna/

    # Gmail sends are not offered on /admin/mcps, where only the digest would show.
    assert MCP.list_pending_tool_approvals(user, except_server_names: ["gmail"]) == []
    assert {:error, :not_found} = MCP.decide_tool_approval(user, id, "approved", except_server_names: ["gmail"])

    assert {:error, :not_found} = Gmail.decide_send(insert_user!(), id, "approved")
    assert {:ok, %{status: "approved"}} = Gmail.decide_send(user, id, "approved")

    # Someone edits the draft after the approval: the send is refused.
    Process.put(:draft, draft_payload("Renewal", "Price is 100k"))
    assert {:error, message} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    assert message =~ "changed after it was approved"
    refute_received :sent

    # Restoring the approved content sends exactly once.
    Process.put(:draft, approved)
    assert {:ok, %{message_id: "sent-1"}} = execute_tool(SendMyGmailDraft, agent_conn(user), %{"draft_id" => "draft-1"})
    assert_received :sent

    assert {:error, message} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    assert message =~ "needs the mailbox owner's approval"
    refute_received :sent

    activity = Repo.get_by!(Activity, action: "connection.gmail_draft_sent", actor_id: user.id)
    assert activity.metadata["recipient_count"] == 2
    refute JSON.encode!(activity.metadata) =~ ~r/Renewal|10k|anna/
  end

  test "approval is refused once the draft changed after the request, and expired approvals never send" do
    user = insert_google!([Gmail.compose_scope()])
    Process.put(:draft, draft_payload("Renewal", "Price is 10k"))
    send_gmail()

    assert {:error, _} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    [%{id: id}] = MCP.list_pending_tool_approvals(user, server_names: ["gmail"])

    Process.put(:draft, draft_payload("Renewal", "Price is 100k"))
    assert [%{status: :changed}] = Gmail.pending_sends(user)
    assert {:error, {:changed, _}} = Gmail.decide_send(user, id, "approved")

    Process.put(:draft, draft_payload("Renewal", "Price is 10k"))
    assert {:ok, _} = Gmail.decide_send(user, id, "approved")

    Repo.update_all(ToolApproval, set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)])
    assert {:error, _} = SendMyGmailDraft.execute(agent_conn(user), %{"draft_id" => "draft-1"})
    refute_received :sent
  end

  test "drafts are hidden from and refused to shared identities, and sending needs a person's MCP session" do
    user = insert_google!([Gmail.compose_scope()])
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)
    stub(Req, :request, fn _ -> flunk("shared identities must not reach Gmail") end)
    slack = %{assigns: %{current_user: user, audit_interface: "slack"}}

    response = Server.handle_message(slack, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    names = Enum.map(response["result"]["tools"], & &1["name"])

    for module <- [GetMyGmailDraft, CreateMyGmailDraft, UpdateMyGmailDraft, SendMyGmailDraft] do
      refute module.name() in names
      assert {:error, "Personal Gmail is unavailable to shared Slack identities."} = module.execute(slack, %{})
    end

    for conn <- [
          %{assigns: %{current_user: user, mcp_claims: %{"slack_agent" => true}}},
          %{assigns: %{current_user: user, audit_interface: "worker"}}
        ] do
      assert {:error, _} = SendMyGmailDraft.execute(conn, %{"draft_id" => "draft-1"})
    end
  end

  test "the MCP audit trail never keeps draft recipients or content" do
    user = insert_user!()
    stub(Proxy, :call_hoisted_tool, fn _, _, _ -> :not_proxy_tool end)

    Server.handle_message(agent_conn(user), %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "create_my_gmail_draft",
        "arguments" => %{"to" => ["lawyer@example.com"], "subject" => "Settlement", "body" => "Confidential"}
      }
    })

    activity = Repo.get_by!(Activity, action: "mcp.tool_called", actor_id: user.id)
    assert activity.metadata["arguments"] == %{}
  end

  defp draft_payload(subject, body, opts \\ []) do
    headers =
      [
        %{"name" => "To", "value" => "anna@example.com"},
        %{"name" => "Cc", "value" => "ben@example.org"},
        %{"name" => "Subject", "value" => subject}
      ] ++
        if(reply = opts[:in_reply_to], do: [%{"name" => "In-Reply-To", "value" => reply}], else: [])

    %{
      "id" => "draft-1",
      "message" => %{
        "id" => "msg-1",
        "threadId" => "thread-1",
        "payload" => %{
          "mimeType" => "text/plain",
          "headers" => headers,
          "body" => %{"data" => Base.url_encode64(body)}
        }
      }
    }
  end

  defp send_gmail do
    gmail(fn
      "GET", "/gmail/v1/users/me/drafts/draft-1", conn ->
        Req.Test.json(conn, Process.get(:draft))

      "POST", "/gmail/v1/users/me/drafts/send", conn ->
        assert json_body(conn) == %{"id" => "draft-1"}
        send(self(), :sent)
        Req.Test.json(conn, %{"id" => "sent-1", "threadId" => "thread-1"})
    end)
  end

  defp gmail(handler) do
    stub(Req, :request, fn opts ->
      plug = fn conn -> handler.(conn.method, conn.request_path, Plug.Conn.fetch_query_params(conn)) end
      Req.request(Req.new(Keyword.put(opts, :plug, plug)), [])
    end)
  end

  defp json_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    JSON.decode!(body)
  end

  # A minimal RFC 5322 reader for the single-part messages Atlas writes.
  defp parse(raw) do
    [head, body] = raw |> Base.url_decode64!(padding: false) |> String.split("\r\n\r\n", parts: 2)

    headers =
      head
      |> String.replace("\r\n ", " ")
      |> String.split("\r\n")
      |> Map.new(fn line ->
        [name, value] = String.split(line, ": ", parts: 2)
        {String.downcase(name), value}
      end)

    {headers, body |> String.replace("\r\n", "") |> Base.decode64!()}
  end

  defp decode_words(value) do
    ~r/=\?UTF-8\?B\?([^?]+)\?=/
    |> Regex.scan(value)
    |> Enum.map_join(fn [_, encoded] -> Base.decode64!(encoded) end)
  end

  defp agent_conn(user), do: %{assigns: %{current_user: user, audit_interface: "mcp"}}

  defp insert_google!(scopes) do
    user = insert_user!()

    %Connection{user_id: user.id, provider: "google"}
    |> Connection.changeset(%{
      provider_user_id: "google-#{user.id}",
      account_name: user.email,
      access_token: "own-token",
      refresh_token: "refresh",
      scopes: scopes
    })
    |> Repo.insert!()

    user
  end
end
