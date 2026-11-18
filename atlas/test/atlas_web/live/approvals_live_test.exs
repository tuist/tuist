defmodule AtlasWeb.ApprovalsLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Config
  alias Atlas.Connections.Connection
  alias Atlas.Connections.Gmail
  alias Atlas.MCP
  alias Atlas.Repo

  setup do
    stub(Config, :credentials, fn _ -> %{client_id: "test-client", client_secret: "test-secret"} end)
    :ok
  end

  test "requires browser sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/approvals")
  end

  test "the agent's link opens only its own request, and only for the mailbox owner", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {other_conn, other} = log_in_user(build_conn())

    for owner <- [user, other] do
      owner |> insert_connection!("google") |> Ecto.Changeset.change(scopes: [Gmail.compose_scope()]) |> Repo.update!()
    end

    {:ok, gmail} =
      Agent.start_link(fn ->
        %{to: "anna@example.com", cc: "", subject: "Kickoff", body: "See you Tuesday", html: false, puts: 0, sent: 0}
      end)

    stub_gmail(gmail)
    assert {:error, {:approval_required, first, false}} = Gmail.send_draft(user, "draft-1")
    assert {:error, {:approval_required, foreign, false}} = Gmail.send_draft(other, "draft-1")
    Agent.update(gmail, &%{&1 | subject: "Follow-up"})
    assert {:error, {:approval_required, second, false}} = Gmail.send_draft(user, "draft-1")

    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#approvals-link [data-selected]")
    assert has_element?(view, "#gmail-approval-#{first.id}")
    assert has_element?(view, "#gmail-approval-#{second.id}")
    refute has_element?(view, "#gmail-approval-#{foreign.id}")

    {:ok, view, _html} = live(conn, ~p"/approvals/#{second.id}")
    assert has_element?(view, "#gmail-approval-subject-#{second.id}", "Follow-up")
    refute has_element?(view, "#gmail-approval-#{first.id}")
    assert has_element?(view, "#approvals-all[href='/approvals']")

    # Approving from the deep link leaves the page explaining the request is settled.
    view |> element("#gmail-approval-approve-#{second.id}") |> render_click()
    assert Repo.reload!(second).status == "approved"
    assert has_element?(view, "#flash-info", "Approved")
    assert has_element?(view, "#approval-not-pending")

    # Someone else's request reads as not pending and cannot be decided.
    {:ok, view, _html} = live(conn, ~p"/approvals/#{foreign.id}")
    assert has_element?(view, "#approval-not-pending")
    refute has_element?(view, "#gmail-approval-#{foreign.id}")
    assert Repo.reload!(foreign).status == "pending"

    {:ok, view, _html} = live(other_conn, ~p"/approvals/#{foreign.id}")
    assert has_element?(view, "#gmail-approval-#{foreign.id}")
  end

  test "a person without admin access decides their own gated MCP calls, such as a cluster elevation", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {_other_conn, other} = log_in_user(build_conn())
    elevation = %{"env" => "canary", "thread_id" => "T-1", "intent" => "Uncordon a runner", "duration_minutes" => 30}

    assert {:approval_required, approval} =
             MCP.authorize_tool_call(user, "tuist-ops", "request-cluster-elevation", elevation)

    assert {:approval_required, foreign} =
             MCP.authorize_tool_call(other, "tuist-ops", "request-cluster-elevation", elevation)

    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#tool-approval-tool-#{approval.id}", "tuist-ops/request-cluster-elevation")
    assert has_element?(view, "#tool-approval-arguments-#{approval.id}", ~s("intent": "Uncordon a runner"))
    refute has_element?(view, "#tool-approval-#{foreign.id}")
    refute has_element?(view, "#approvals-empty")

    # Someone else's request reads as not pending and cannot be decided.
    {:ok, foreign_view, _html} = live(conn, ~p"/approvals/#{foreign.id}")
    assert has_element?(foreign_view, "#approval-not-pending")
    refute has_element?(foreign_view, "#tool-approval-#{approval.id}")

    {:ok, view, _html} = live(conn, ~p"/approvals/#{approval.id}")
    view |> element("#tool-approval-approve-#{approval.id}") |> render_click()
    assert Repo.reload!(approval).status == "approved"
    assert Repo.reload!(foreign).status == "pending"
    assert has_element?(view, "#flash-info", "Approved")
    assert has_element?(view, "#approval-not-pending")

    assert %{interface: "dashboard", actor_id: actor_id} =
             Repo.get_by!(Activity, action: "mcp_tool_approval.approved", target_id: approval.id)

    assert actor_id == user.id
  end

  test "shows an empty state when nothing is waiting", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#approvals-empty")
    refute has_element?(view, "#gmail-send-requests")
  end

  test "the mailbox owner reviews a send request against the live draft before approving it", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    google = insert_connection!(user, "google")
    google |> Ecto.Changeset.change(scopes: [Gmail.compose_scope()]) |> Repo.update!()
    # The LiveView reads the draft from its own process.
    {:ok, draft_body} = Agent.start_link(fn -> "See you Tuesday" end)

    stub(Req, :request, fn opts ->
      plug = fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/gmail/v1/users/me/drafts/draft-1"} ->
            Req.Test.json(conn, %{
              "id" => "draft-1",
              "message" => %{
                "id" => "msg-1",
                "threadId" => "thread-1",
                "payload" => %{
                  "mimeType" => "text/plain",
                  "headers" => [
                    %{"name" => "To", "value" => "anna@example.com"},
                    %{"name" => "Subject", "value" => "Kickoff"}
                  ],
                  "body" => %{"data" => Base.url_encode64(Agent.get(draft_body, & &1))}
                }
              }
            })
        end
      end

      Req.request(Req.new(Keyword.put(opts, :plug, plug)), [])
    end)

    assert {:error, {:approval_required, approval, false}} = Gmail.send_draft(user, "draft-1")

    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#gmail-approval-to-#{approval.id}", "anna@example.com")
    assert has_element?(view, "#gmail-approval-subject-#{approval.id}", "Kickoff")
    assert has_element?(view, "#gmail-approval-body-#{approval.id}", "See you Tuesday")

    # The draft changes while the page is open: approving it must fail.
    Agent.update(draft_body, fn _ -> "See you never" end)
    view |> element("#gmail-approval-approve-#{approval.id}") |> render_click()
    assert Repo.reload!(approval).status == "pending"
    assert has_element?(view, "#gmail-approval-changed-#{approval.id}")
    refute has_element?(view, "#gmail-approval-approve-#{approval.id}")

    Agent.update(draft_body, fn _ -> "See you Tuesday" end)
    {:ok, view, _html} = live(conn, ~p"/approvals")
    view |> element("#gmail-approval-approve-#{approval.id}") |> render_click()
    assert Repo.reload!(approval).status == "approved"
    refute has_element?(view, "#gmail-approval-#{approval.id}")
    assert Repo.get_by!(Activity, action: "mcp_tool_approval.approved", target_id: approval.id).interface == "dashboard"
  end

  test "the owner can edit a draft before approving, and the approval pins the edited content", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    google = insert_connection!(user, "google")
    google |> Ecto.Changeset.change(scopes: [Gmail.compose_scope()]) |> Repo.update!()

    {:ok, gmail} =
      Agent.start_link(fn ->
        %{to: "anna@example.com", cc: "", subject: "Kickoff", body: "See you Tuesday", html: false, puts: 0, sent: 0}
      end)

    stub_gmail(gmail)
    assert {:error, {:approval_required, approval, false}} = Gmail.send_draft(user, "draft-1")

    {:ok, view, _html} = live(conn, ~p"/approvals")
    view |> element("#gmail-approval-edit-#{approval.id}") |> render_click()
    refute has_element?(view, "#gmail-approval-approve-#{approval.id}")

    # Invalid recipients are refused before anything reaches Gmail, keeping the edit.
    view
    |> form("#gmail-approval-form-#{approval.id}", draft: %{to: "Anna <anna@example.com>"})
    |> render_submit()

    assert Agent.get(gmail, & &1.puts) == 0
    assert Repo.reload!(approval).status == "pending"
    assert has_element?(view, "#gmail-approval-edit-to-#{approval.id}[value='Anna <anna@example.com>']")

    view
    |> form("#gmail-approval-form-#{approval.id}",
      draft: %{to: "anna@example.com, ben@example.org", subject: "Kickoff moved", body: "See you Thursday\r\ninstead"}
    )
    |> render_submit()

    assert %{to: "anna@example.com, ben@example.org", subject: "Kickoff moved", body: "See you Thursday\ninstead"} =
             Agent.get(gmail, & &1)

    approved = Repo.reload!(approval)
    assert approved.status == "approved"
    refute approved.arguments == approval.arguments
    refute has_element?(view, "#gmail-approval-#{approval.id}")

    # The agent's unchanged retry sends what the owner saved, exactly once.
    assert {:ok, _sent} = Gmail.send_draft(user, "draft-1")
    assert Agent.get(gmail, & &1.sent) == 1
  end

  test "drafts that a plain-text save would change cannot be edited here", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    google = insert_connection!(user, "google")
    google |> Ecto.Changeset.change(scopes: [Gmail.compose_scope()]) |> Repo.update!()

    {:ok, gmail} =
      Agent.start_link(fn ->
        %{to: "anna@example.com", cc: "", subject: "Kickoff", body: "See you", html: true, puts: 0, sent: 0}
      end)

    stub_gmail(gmail)
    assert {:error, {:approval_required, approval, false}} = Gmail.send_draft(user, "draft-1")

    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#gmail-approval-approve-#{approval.id}")
    refute has_element?(view, "#gmail-approval-edit-#{approval.id}")
  end

  # A Gmail draft held in an Agent so the LiveView process sees the same one.
  defp stub_gmail(gmail) do
    stub(Req, :request, fn opts ->
      plug = fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/gmail/v1/users/me/drafts/draft-1"} ->
            Req.Test.json(conn, draft_json(Agent.get(gmail, & &1)))

          {"PUT", "/gmail/v1/users/me/drafts/draft-1"} ->
            save_draft(gmail, conn)

          {"POST", "/gmail/v1/users/me/drafts/send"} ->
            Agent.update(gmail, &%{&1 | sent: &1.sent + 1})
            Req.Test.json(conn, %{"id" => "sent-1", "threadId" => "thread-1"})
        end
      end

      Req.request(Req.new(Keyword.put(opts, :plug, plug)), [])
    end)
  end

  defp save_draft(gmail, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"message" => %{"raw" => raw}} = JSON.decode!(body)
    [head, encoded] = raw |> Base.url_decode64!(padding: false) |> String.split("\r\n\r\n", parts: 2)
    headers = Map.new(String.split(head, "\r\n"), &List.to_tuple(String.split(&1, ": ", parts: 2)))

    Agent.update(gmail, fn state ->
      %{
        state
        | to: headers["To"],
          cc: headers["Cc"] || "",
          subject: headers["Subject"],
          body: encoded |> String.replace("\r\n", "") |> Base.decode64!(),
          puts: state.puts + 1
      }
    end)

    Req.Test.json(conn, %{"id" => "draft-1", "message" => %{"id" => "msg-2", "threadId" => "thread-1"}})
  end

  defp draft_json(state) do
    text = %{"mimeType" => "text/plain", "body" => %{"data" => Base.url_encode64(state.body)}}
    html = %{"mimeType" => "text/html", "body" => %{"data" => Base.url_encode64("<p>#{state.body}</p>")}}

    headers =
      [%{"name" => "To", "value" => state.to}, %{"name" => "Subject", "value" => state.subject}] ++
        if(state.cc == "", do: [], else: [%{"name" => "Cc", "value" => state.cc}])

    payload =
      if state.html,
        do: %{"mimeType" => "multipart/alternative", "headers" => headers, "parts" => [text, html]},
        else: Map.put(text, "headers", headers)

    %{"id" => "draft-1", "message" => %{"id" => "msg-1", "threadId" => "thread-1", "payload" => payload}}
  end

  defp insert_connection!(user, provider) do
    %Connection{user_id: user.id, provider: provider}
    |> Connection.changeset(%{
      provider_user_id: "42",
      account_name: "octocat",
      access_token: "private-access",
      refresh_token: "private-refresh"
    })
    |> Repo.insert!()
  end
end
