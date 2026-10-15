defmodule TuistWeb.ProjectAutomationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Revision
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistWeb.Errors.NotFoundError

  defp open(conn, organization, project, automation) do
    live(
      conn,
      ~p"/#{organization.account.name}/#{project.name}/settings/automations/#{automation.id}"
    )
  end

  test "keeps restricted automation fields out of public-project image URLs", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, project} = Projects.update_project(project, %{visibility: :public})
    automation = AutomationsFixtures.automation_alert_fixture(project: project, name: "Internal quarantine policy")
    path = ~p"/#{organization.account.name}/#{project.name}/settings/automations/#{automation.id}"
    html = conn |> get(path) |> html_response(:ok)
    document = Floki.parse_document!(html)

    assert Floki.attribute(document, "meta[property='og:image']", "content") == [
             Tuist.Environment.app_url(path: "/images/open-graph/dashboard/settings.png")
           ]
  end

  test "shows cache-key evidence and links to both builds", context do
    {:ok, automation} =
      Automations.create_alert(%{
        project_id: context.project.id,
        name: "Cache key consistency",
        monitor_type: "cache_key_consistency",
        trigger_actions: [%{"type" => "send_slack", "channel" => "C1", "message" => "{{build.summary}}"}]
      })

    first = UUIDv7.generate()
    second = UUIDv7.generate()

    Tuist.Automations.Builds.persist(automation, [
      %{
        source: "xcode_compilation",
        unit_key: "Compile Core.swift",
        unit_name: "Compile Core.swift",
        commit_sha: "abcdef0123456789",
        first_key: "hash-a",
        second_key: "hash-b",
        first_run: first,
        second_run: second
      }
    ])

    {:ok, lv, html} = open(context.conn, context.organization, context.project, automation)
    assert html =~ "Cache key findings"
    assert html =~ "hash-a"
    assert html =~ "hash-b"

    assert has_element?(
             lv,
             "a[href='/#{context.organization.account.name}/#{context.project.name}/builds/build-runs/#{first}']",
             "Build A"
           )

    assert has_element?(
             lv,
             "a[href='/#{context.organization.account.name}/#{context.project.name}/builds/build-runs/#{second}']",
             "Build B"
           )

    assert render_hook(lv, "show_more_build_findings", %{}) =~ "Compile Core.swift"
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
