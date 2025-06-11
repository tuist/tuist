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
end
