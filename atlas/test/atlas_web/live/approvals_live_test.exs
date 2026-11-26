defmodule AtlasWeb.ApprovalsLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Connection
  alias Atlas.MCP
  alias Atlas.MCP.ToolApproval
  alias Atlas.MCP.ToolCase
  alias Atlas.MCP.Tools.DownloadMySlackFile
  alias Atlas.MCP.Tools.PostMySlackMessage
  alias Atlas.Repo

  test "requires browser sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/approvals")
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

  describe "Slack post approvals" do
    @contract "Acme MSA, confidential: price 120k/year"

    test "name the conversation, flag Slack Connect and preview a file the person downloaded from Slack", %{
      conn: conn
    } do
      {conn, user} = log_in_user(conn)
      insert_slack!(user)

      # An agent downloads a customer contract from Slack ...
      slack(fn
        %{request_path: "/api/files.info"} = conn ->
          Req.Test.json(conn, %{"ok" => true, "file" => slack_file()})

        %{host: "files.slack.com"} = conn ->
          Plug.Conn.send_resp(conn, 200, @contract)

        %{request_path: "/api/conversations.info"} = conn ->
          assert Plug.Conn.fetch_query_params(conn).query_params["channel"] == "C0EXT"

          Req.Test.json(conn, %{
            "ok" => true,
            "channel" => %{"id" => "C0EXT", "name" => "acme-tuist", "is_channel" => true, "is_ext_shared" => true}
          })
      end)

      tool_conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}

      assert {:ok, %{download_url: url}} =
               ToolCase.execute_tool(DownloadMySlackFile, tool_conn, %{"file_id" => "F0MSA"})

      %URI{path: path, query: query} = URI.parse(url)
      assert build_conn() |> get(path <> "?" <> query) |> response(200) == @contract

      # ... and asks to post it, renamed, to a Slack Connect channel.
      args = %{
        "channel_id" => "C0EXT",
        "files" => [%{"filename" => "notes.txt", "content_base64" => Base.encode64(@contract)}]
      }

      assert {:error, "Posting to Slack" <> _} = PostMySlackMessage.execute(tool_conn, args)
      approval = Repo.get_by!(ToolApproval, user_id: user.id, server_name: "slack", status: "pending")

      stub(Req, :request, fn _ -> flunk("the approval page must not call Slack") end)
      {:ok, view, _html} = live(conn, ~p"/approvals/#{approval.id}")

      # The person sees where the post goes, that people outside Tuist are in
      # it, and what the file is, not just an id, a name and a hash.
      assert has_element?(view, "#tool-approval-slack-channel-#{approval.id}", "#acme-tuist")
      assert has_element?(view, "#tool-approval-slack-external-#{approval.id}", "External")
      assert has_element?(view, "#tool-approval-slack-file-0-#{approval.id}", "notes.txt")
      assert has_element?(view, "#tool-approval-slack-file-source-0-#{approval.id}", "Acme MSA.txt")
      assert has_element?(view, "#tool-approval-slack-file-preview-0-#{approval.id}", "price 120k/year")

      # The display context does not change what the approval covers.
      assert approval.arguments == %{
               "channel_id" => "C0EXT",
               "files" => [
                 %{
                   "filename" => "notes.txt",
                   "byte_size" => byte_size(@contract),
                   "sha256" => :sha256 |> :crypto.hash(@contract) |> Base.encode16(case: :lower)
                 }
               ]
             }

      # The audit trail shows where the post was going, never the file's content.
      requested = Repo.get_by!(Activity, action: "mcp_tool_approval.requested", target_id: approval.id)

      assert requested.metadata["context"]["channel"] == %{
               "id" => "C0EXT",
               "name" => "acme-tuist",
               "kind" => "channel",
               "external" => true
             }

      refute JSON.encode!(requested.metadata) =~ "120k"
    end

    test "say so when Atlas cannot look up the conversation", %{conn: conn} do
      {conn, user} = log_in_user(conn)
      insert_slack!(user)

      # Connections made before Atlas asked for channels:read cannot look it up.
      slack(fn %{request_path: "/api/conversations.info"} = conn ->
        Req.Test.json(conn, %{"ok" => false, "error" => "missing_scope"})
      end)

      tool_conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
      PostMySlackMessage.execute(tool_conn, %{"channel_id" => "D0DM", "text" => "hi"})
      approval = Repo.get_by!(ToolApproval, user_id: user.id, server_name: "slack", status: "pending")

      {:ok, view, _html} = live(conn, ~p"/approvals/#{approval.id}")
      assert has_element?(view, "#tool-approval-slack-unverified-#{approval.id}", "Reconnect Slack")
      refute has_element?(view, "#tool-approval-slack-external-#{approval.id}")
    end
  end

  test "shows an empty state when nothing is waiting", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#approvals-empty")
    refute has_element?(view, "#gmail-send-requests")
  end

  test "legacy Gmail requests remain stored but cannot be viewed or approved", %{conn: conn} do
    {conn, user} = log_in_user(conn)

    {:approval_required, legacy} =
      MCP.authorize_tool_call(user, "gmail", "send-draft", %{"draft_id" => "draft-1", "digest" => "old"})

    stub(Req, :request, fn _ -> flunk("approvals must not read Gmail") end)
    {:ok, view, _html} = live(conn, ~p"/approvals")
    assert has_element?(view, "#approvals-empty")
    refute has_element?(view, "#gmail-send-requests")
    refute has_element?(view, "#tool-approval-#{legacy.id}")

    {:ok, view, _html} = live(conn, ~p"/approvals/#{legacy.id}")
    assert has_element?(view, "#approval-not-pending")
    refute has_element?(view, "#gmail-send-requests")
    render_click(view, "decide_tool_approval", %{"id" => legacy.id, "decision" => "approved"})
    assert Repo.reload!(legacy).status == "pending"
  end

  defp slack_file do
    %{
      "id" => "F0MSA",
      "name" => "Acme MSA.txt",
      "title" => "Acme MSA",
      "mimetype" => "text/plain",
      "filetype" => "text",
      "size" => byte_size(@contract),
      "url_private_download" => "https://files.slack.com/files-pri/T1-F0MSA/download/msa.txt"
    }
  end

  defp insert_slack!(user) do
    %Connection{user_id: user.id, provider: "slack"}
    |> Connection.changeset(%{
      provider_user_id: "U#{user.id}",
      account_name: "slack-user",
      workspace_id: "T1",
      access_token: "xoxp-own",
      scopes: ~w(search:read chat:write channels:history files:read files:write channels:read)
    })
    |> Repo.insert!()
  end

  defp slack(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
