defmodule TuistWeb.ProjectAutomationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Revision
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
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

  test "shows the one-time request in history without making it part of the condition", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    automation = AutomationsFixtures.automation_alert_fixture(project: project)

    {:ok, automation} =
      Automations.update_alert(automation, %{
        trigger_config: Map.put(automation.trigger_config, "apply_actions_to_existing_matches", true)
      })

    {:ok, live_view, _html} = open(conn, organization, project, automation)
    refute has_element?(live_view, "[data-part='configuration-card']", "Requested actions for existing matches")
    assert has_element?(live_view, "[data-part='history-card']", "Requested actions for existing matches")
  end

  test "lists the tests the automation matched, most recently matched first", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    automation = AutomationsFixtures.automation_alert_fixture(project: project)
    matched_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)

    test_cases =
      Enum.map(1..23, fn index ->
        name = "testMatched#{String.pad_leading(Integer.to_string(index), 2, "0")}"

        IngestRepo.insert!(
          RunsFixtures.test_case_fixture(project_id: project.id, name: name, module_name: "MatchedTests")
        )
      end)

    Enum.with_index(test_cases, fn test_case, index ->
      Automations.create_alert_event(%{
        alert_id: automation.id,
        baseline_generation: automation.baseline_generation,
        test_case_id: test_case.id,
        status: "triggered",
        triggered_at: NaiveDateTime.add(matched_at, index, :second)
      })
    end)

    now = NaiveDateTime.utc_now()

    Automations.create_alert_event(%{
      alert_id: automation.id,
      baseline_generation: automation.baseline_generation,
      test_case_id: hd(test_cases).id,
      status: "recovered",
      triggered_at: now,
      recovered_at: now
    })

    {:ok, live_view, _html} = open(conn, organization, project, automation)

    assert has_element?(live_view, "#matched-tests-table", "testMatched23")
    assert has_element?(live_view, "#matched-tests-table", "MatchedTests")
    refute has_element?(live_view, "#matched-tests-table", "testMatched03")
    refute has_element?(live_view, "#matched-tests-table", "testMatched01")

    live_view |> element("#show-more-matched-tests") |> render_click()

    assert has_element?(live_view, "#matched-tests-table", "testMatched03")
    assert has_element?(live_view, "#matched-tests-table", "testMatched02")
    refute has_element?(live_view, "#matched-tests-table", "testMatched01")
    refute has_element?(live_view, "#show-more-matched-tests")
  end

  test "does not list matched tests for event-driven automations", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    automation =
      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "test_updated",
        trigger_config: %{"events" => ["marked_flaky"]}
      )

    {:ok, live_view, _html} = open(conn, organization, project, automation)

    refute has_element?(live_view, "#matched-tests")
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
