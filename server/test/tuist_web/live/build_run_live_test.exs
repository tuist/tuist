defmodule TuistWeb.BuildRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)
    %{conn: conn, user: user}
  end

  test "shows details of a build run", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App"
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    assert has_element?(lv, "h1", "App")
  end

  test "shows download button when build run has result bundle", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    alias TuistTestSupport.Fixtures.CommandEventsFixtures
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App"
      )

    # Create a command event associated with this build run
    _command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        build_run_id: build_run.id,
        command_arguments: ["build", "App"]
      )

    stub(CommandEvents, :has_result_bundle?, fn _ -> true end)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    assert has_element?(lv, "a", "Download result")
  end

  test "hides download button when build run has no result bundle", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App"
      )

    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    refute has_element?(lv, "a", "Download result")
  end

  test "shows command information when build run has associated command event", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    alias TuistTestSupport.Fixtures.CommandEventsFixtures
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App"
      )

    # Create a command event associated with this build run
    _command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        build_run_id: build_run.id,
        command_arguments: ["build", "App"]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    assert has_element?(lv, "[data-part='command-label']")
  end

  test "shows CI Run button with GitHub CI metadata", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        ci_provider: :github,
        ci_run_id: "1234567890",
        ci_project_handle: "tuist/tuist"
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    assert has_element?(lv, "a", "CI Run")
    assert has_element?(lv, ~s|a[href="https://github.com/tuist/tuist/actions/runs/1234567890"]|)
  end

  test "hides CI Run button when build run has no CI metadata", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App"
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    refute has_element?(lv, "a", "CI Run")
  end

  test "shows cache tab when build has cacheable tasks", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    cacheable_tasks = [
      %{type: :swift, status: :hit_remote, key: "cache-key-1"},
      %{type: :clang, status: :hit_local, key: "cache-key-2"},
      %{type: :swift, status: :miss, key: "cache-key-3"}
    ]

    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        cacheable_tasks: cacheable_tasks
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then - Check that the Xcode Cache tab is present in the horizontal tab menu
    assert has_element?(lv, ".noora-tab-menu-horizontal-item", "Xcode Cache")

    # When clicking on the xcode cache tab
    lv |> element(".noora-tab-menu-horizontal-item", "Xcode Cache") |> render_click()

    # Then it should show the summary statistics
    assert has_element?(lv, "[data-part='title']", "Task hits")
    assert has_element?(lv, "[data-part='value']", "2")
    assert has_element?(lv, "[data-part='title']", "Task misses")
    assert has_element?(lv, "[data-part='value']", "1")
    assert has_element?(lv, "[data-part='title']", "Hit rate")
  end

  test "hides cache tab when build has no cacheable tasks", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        cacheable_tasks: []
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then - Check that the Xcode Cache tab is not present in the horizontal tab menu
    refute has_element?(lv, ".noora-tab-menu-horizontal-item", "Xcode Cache")
  end
end
