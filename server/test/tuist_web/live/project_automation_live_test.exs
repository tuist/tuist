defmodule TuistWeb.ProjectAutomationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Automations
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  defp open(conn, organization, project, automation) do
    live(
      conn,
      ~p"/#{organization.account.name}/#{project.name}/settings/automations/#{automation.id}"
    )
  end

  test "shows the current configuration and edit history", %{
    conn: conn,
    organization: organization,
    project: project,
    user: user
  } do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        project: project,
        name: "Quarantine flaky tests",
        recovery_enabled: true,
        recovery_config: %{"window_type" => "last_days", "window" => "14d"},
        recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
      )

    {:ok, automation} =
      Automations.update_alert(
        automation,
        %{
          name: "Auto-quarantine flaky tests",
          recovery_enabled: false
        },
        actor: user,
        source: "dashboard"
      )

    automation =
      Enum.reduce(1..4, automation, fn index, automation ->
        {:ok, automation} =
          Automations.update_alert(
            automation,
            %{name: "Auto-quarantine flaky tests #{index}"},
            actor: user,
            source: "dashboard"
          )

        automation
      end)

    {:ok, live_view, html} = open(conn, organization, project, automation)

    assert has_element?(live_view, "#project-automation")
    assert html =~ "Auto-quarantine flaky tests"
    assert html =~ "Current configuration"
    assert html =~ "Edit history"
    assert html =~ "Automation renamed"
    assert html =~ "Recovery disabled"
    assert html =~ "Quarantine flaky tests"
    assert html =~ "the dashboard"
    assert has_element?(live_view, "#show-more-history", "Show more")
    refute html =~ "Automation created"

    html = live_view |> element("#show-more-history") |> render_click()

    assert html =~ "Automation created"
    refute has_element?(live_view, "#show-more-history")
  end

  test "raises not found when the automation does not belong to the project", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    other_project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()
    automation = AutomationsFixtures.automation_alert_fixture(project: other_project)

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      open(conn, organization, project, automation)
    end
  end
end
