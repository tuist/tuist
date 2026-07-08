defmodule TuistWeb.BuildRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

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
        ci_provider: "github",
        ci_run_id: "1234567890",
        ci_project_handle: "tuist/tuist"
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    assert has_element?(lv, "a", "CI Run")
    assert has_element?(lv, ~s|a[href="https://github.com/tuist/tuist/actions/runs/1234567890"]|)
  end

  test "shows Runner Job button when a GitHub build run matches a runner job", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 42_101,
        account_id: organization.account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: 421_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        ci_run_id: "421010"
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    assert has_element?(lv, "a", "Runner Job")
    assert has_element?(lv, ~s|a[href="/#{organization.account.name}/runners/runs/421010/jobs/42101"]|)
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

  test "shows module cache tab when associated command event has binary cache data", %{
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

    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        build_run_id: build_run.id,
        command_arguments: ["build", "App"]
      )

    xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)
    xcode_project = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    _xcode_target =
      XcodeFixtures.xcode_target_fixture(
        name: "AppFramework",
        xcode_project_id: xcode_project.id,
        binary_cache_hash: "AppFramework-hash",
        binary_cache_hit: :remote
      )

    # When
    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}?tab=module-cache"
      )

    # Then
    assert has_element?(lv, ".noora-tab-menu-horizontal-item", "Module Cache")
    assert has_element?(lv, "table span", "AppFramework")
    assert has_element?(lv, "table span", "AppFramework-hash")
  end

  test "shows module cache tab for a local build via the generation it points at", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    # A local Xcode build has no command event of its own; the breakdown comes from the generate
    # command event that uploaded the graph, which the build points at by that command event's id.
    generation_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        command_arguments: ["generate"]
      )

    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        generation_id: generation_event.id
      )

    xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: generation_event.id)
    xcode_project = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

    _xcode_target =
      XcodeFixtures.xcode_target_fixture(
        name: "AppFramework",
        xcode_project_id: xcode_project.id,
        binary_cache_hash: "AppFramework-hash",
        binary_cache_hit: :remote
      )

    # When
    {:ok, lv, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}?tab=module-cache"
      )

    # Then
    assert has_element?(lv, ".noora-tab-menu-horizontal-item", "Module Cache")
    assert has_element?(lv, "table span", "AppFramework")
    assert has_element?(lv, "table span", "AppFramework-hash")
  end

  test "hides module cache tab when build has no binary cache data", %{
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

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        build_run_id: build_run.id,
        command_arguments: ["build", "App"]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    # Then
    refute has_element?(lv, ".noora-tab-menu-horizontal-item", "Module Cache")
  end
end
