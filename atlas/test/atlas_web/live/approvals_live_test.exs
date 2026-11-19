defmodule AtlasWeb.ApprovalsLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.Audit.Activity
  alias Atlas.MCP
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
end
