defmodule TuistWeb.ProjectAutomationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  test "renders the project automations page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

    assert html =~ "Automations"
    assert html =~ "Flaky test detection"
    assert html =~ "Test quarantine"
  end

  test "toggles auto-quarantine setting", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

    assert project.auto_quarantine_flaky_tests

    html = lv |> element(~s|#auto-quarantine-toggle|) |> render_click()

    assert html =~ "Auto-quarantine flaky tests"
  end
end
