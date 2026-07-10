defmodule TuistWeb.BuildRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias Tuist.IngestRepo
  alias Tuist.Runners.Job
  alias Tuist.Runners.JobSteps
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

  test "surfaces linked runner CI context when build run came from a Tuist runner job", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    seed_runner_job(organization.account, 31_301, 313_010, "Build")

    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: organization.account.id,
        scheme: "App",
        duration: 120_000,
        ci_provider: "github",
        ci_run_id: "313010",
        ci_project_handle: "tuist/tuist",
        is_ci: true
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    assert has_element?(lv, "[data-part='ci-context-card']", "CI Details")
    assert has_element?(lv, "[data-part='ci-context-card'] a", "View more")

    assert has_element?(
             lv,
             ~s|[data-part='ci-context-card'] a[href="/#{organization.account.name}/runners/workflows/tuist/tuist/Server"]|,
             "Server"
           )

    assert has_element?(
             lv,
             ~s|[data-part='ci-context-card'] a[href="/#{organization.account.name}/runners/runs/313010/jobs/31301"]|,
             "Build and test"
           )

    assert has_element?(
             lv,
             ~s|[data-part='ci-context-card'] a[href="/#{organization.account.name}/runners/runs/313010/jobs/31301?tab=overview&step=2"]|,
             "Build ·"
           )

    refute has_element?(lv, "[data-part='ci-context-card'] a", "GitHub")
    refute has_element?(lv, "[data-part='ci-context-card']", "Status")
    refute has_element?(lv, "[data-part='ci-context-card']", "Workflow jobs")
    refute has_element?(lv, "[data-part='ci-context-card']", "Repository")
    refute has_element?(lv, "[data-part='ci-context-card']", "Run ID")
    assert render(lv) =~ "Profile"
    assert render(lv) =~ "tuist-macos"
    refute has_element?(lv, "[data-part='ci-context-card']", "Platform")
    refute has_element?(lv, "[data-part='ci-context-card']", "Build duration")
    assert has_element?(lv, "[data-part='ci-context-card']", "Step")
    assert render(lv) =~ "Build ·"
  end

  test "hides linked runner CI context when no runner job matches the build", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    seed_runner_job(organization.account, 31_302, 313_020, "Deploy", job_name: "Deploy")

    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: organization.account.id,
        scheme: "App",
        ci_provider: "github",
        ci_run_id: "313020",
        ci_project_handle: "tuist/tuist",
        is_ci: true
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_run.id}")

    refute has_element?(lv, "[data-part='ci-context-card']")
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

  defp seed_runner_job(account, workflow_job_id, workflow_run_id, matched_step_name, opts \\ []) do
    enqueued_at = ~U[2026-05-28 10:00:00.000000Z]
    claimed_at = ~U[2026-05-28 10:00:08.000000Z]
    started_at = ~U[2026-05-28 10:00:12.000000Z]
    completed_at = ~U[2026-05-28 10:08:12.000000Z]

    IngestRepo.insert_all(Job, [
      %{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: workflow_run_id,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: Keyword.get(opts, :job_name, "Build and test"),
        head_branch: "main",
        head_sha: "abcdef1234567890",
        status: "completed",
        conclusion: "success",
        enqueued_at: enqueued_at,
        claimed_at: claimed_at,
        started_at: started_at,
        completed_at: completed_at,
        pod_name: "runner-pod-ci-context",
        runner_name: "tuist-runner-ci-context",
        requested_dispatch_label: "tuist-macos",
        updated_at: completed_at
      }
    ])

    :ok =
      JobSteps.record([
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          number: 1,
          name: "Run actions/checkout@v4",
          status: "completed",
          conclusion: "success",
          started_at: started_at,
          completed_at: DateTime.add(started_at, 20, :second)
        },
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          number: 2,
          name: matched_step_name,
          status: "completed",
          conclusion: "success",
          started_at: DateTime.add(started_at, 20, :second),
          completed_at: DateTime.add(started_at, 260, :second)
        }
      ])
  end
end
