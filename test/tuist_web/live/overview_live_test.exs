defmodule TuistWeb.OverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "user123#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        preload: [:account]
      )

    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, organization: organization}
  end

  test "sets the right title", %{conn: conn, organization: organization, project: project} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

    assert html =~ "Overview · tuist-org/tuist · Tuist"
  end

  test "sets the right binary cache hit rate analytics", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: ["A", "B", "C", "D"],
      local_cache_target_hits: ["E", "F"],
      remote_cache_target_hits: [],
      created_at: ~N[2024-04-30 03:00:00]
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

    assert has_element?(lv, ".tuist-widget span", "50.0%")
  end

  test "sets the right average build time", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    RunsFixtures.build_fixture(
      project_id: project.id,
      duration: 1000,
      inserted_at: ~U[2024-04-30 03:00:00Z]
    )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

    assert has_element?(lv, "div[data-part=average-build-time-chart] span", "1.0s")
  end

  test "shows empty states", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")

    assert has_element?(
             lv,
             ".noora-card__section span",
             "Binary cache and selective testing: no data yet"
           )
  end
end
