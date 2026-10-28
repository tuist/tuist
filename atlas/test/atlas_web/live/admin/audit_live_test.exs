defmodule AtlasWeb.Admin.AuditLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Audit

  test "renders audit activities for executives and filters by interface", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{email: "audit-executive@example.com", role: :executive})

    {:ok, _activity} =
      Audit.log("account.updated", %{
        interface: "dashboard",
        actor_email: "dashboard@example.com",
        target_type: "account",
        target_id: "account-id",
        target_label: "Dashboard Account"
      })

    {:ok, _activity} =
      Audit.log("blog_post_idea.created", %{
        interface: "slack",
        actor_name: "Slack User",
        target_type: "blog_post_idea",
        target_id: "idea-id",
        target_label: "Slack Idea"
      })

    filter_params = %{"filter_interface_op" => "==", "filter_interface_val" => "slack"}
    {:ok, view, _html} = live(conn, ~p"/admin/audit?#{filter_params}")

    assert has_element?(view, "#admin-audit")
    assert has_element?(view, "#admin-audit-filters-dropdown")
    assert has_element?(view, "#admin-audit-search-form")
    assert has_element?(view, "#interface")
    assert has_element?(view, "#admin-audit-table")
    assert has_element?(view, "#admin-audit-count", "1 activity")
    assert has_element?(view, ~s(a[data-part="target-link"][href="/commercial/gtm/content/idea-id"]))

    view
    |> form("#admin-audit-search-form", search: %{query: "Slack User"})
    |> render_change()

    assert_patch(
      view,
      ~p"/admin/audit?#{Map.put(filter_params, "q", "Slack User")}"
    )
  end

  test "redirects employees away from the audit page", %{conn: conn} do
    {conn, _employee} = log_in_user(conn, %{email: "audit-employee@example.com", role: :employee})

    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/admin/audit")
  end
end
