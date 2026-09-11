defmodule TuistWeb.ProjectAutomationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Revision
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistWeb.Errors.NotFoundError

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

    # All six revisions land in the same second, and the UUIDv7 that breaks the
    # tie is random within a millisecond, so the creation is pushed back to keep
    # it off the first page of history and the rest on it.
    oldest =
      automation.id
      |> Automations.list_alert_revisions()
      |> Enum.map(& &1.inserted_at)
      |> Enum.min(DateTime)

    Repo.update_all(
      from(r in Revision, where: r.automation_alert_id == ^automation.id and r.event == "created"),
      set: [inserted_at: DateTime.add(oldest, -1, :second)]
    )

    {:ok, live_view, html} = open(conn, organization, project, automation)

    assert has_element?(live_view, "#project-automation")
    assert html =~ "Auto-quarantine flaky tests"
    assert html =~ "Current configuration"
    assert html =~ "Edit history"
    assert html =~ "Automation renamed"
    assert html =~ "the dashboard"
    assert has_element?(live_view, "#show-more-history", "Show more")
    refute html =~ "Automation created"

    html = live_view |> element("#show-more-history") |> render_click()

    assert html =~ "Automation created"
    assert html =~ "Quarantine flaky tests"
    assert html =~ "Recovery disabled"
    refute has_element?(live_view, "#show-more-history")
  end

  test "raises not found when the automation does not belong to the project", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    other_project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()
    automation = AutomationsFixtures.automation_alert_fixture(project: other_project)

    assert_raise NotFoundError, fn ->
      open(conn, organization, project, automation)
    end
  end

  test "raises not found when the automation identifier is malformed", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations/not-a-uuid")
    end
  end
end
