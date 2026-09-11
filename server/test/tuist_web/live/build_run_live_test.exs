defmodule TuistWeb.BuildRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
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

  test "builds without recorded steps or aligned samples hide Timeline", %{
    conn: conn,
    project: project,
    organization: organization
  } do
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
    path = "/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}"
    {:ok, lv, _} = live(conn, path <> "?tab=timeline")
    render_async(lv)
    refute has_element?(lv, "a", "Timeline")
    refute has_element?(lv, "#build-timeline")
    assert has_element?(lv, "a[data-selected]", "Overview")
  end

  test "loads timeline intervals when opening the timeline tab", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    event = %{
      event_id: 1,
      title: "Compile <App>.swift",
      log: "EmitSwiftModule normal arm64\ncd /workspace",
      log_truncated: false,
      target: "App",
      project: "Workspace",
      category: "swiftCompilation",
      start_ms: 100.0,
      duration_ms: 250.0,
      status: "success"
    }

    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, build_steps: [event])
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}")
    refute has_element?(lv, "#build-timeline")
    lv |> element("a", "Timeline") |> render_click()
    render_async(lv)
    assert has_element?(lv, "#build-timeline[phx-hook=BuildTimeline]")
    assert has_element?(lv, ".noora-card", "Build Timeline")
    assert has_element?(lv, ".noora-text-input [data-control=search]")
    refute has_element?(lv, "#timeline-category")
    refute has_element?(lv, "#timeline-status")
    refute has_element?(lv, "[data-control=zoom-in]")
    refute has_element?(lv, "[data-control=pan]")
    refute has_element?(lv, "#build-timeline[data-events]")
    refute render(lv) =~ "Compile &lt;App&gt;.swift"
    [version] = lv |> render() |> Floki.parse_document!() |> Floki.attribute("#build-timeline", "data-version")
    version = String.to_integer(version)
    bootstrap = %{duration: build.duration, machine_metrics: []}

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        selected_tab: "timeline",
        timeline_version: version,
        timeline: AsyncResult.ok(bootstrap)
      }
    }

    assert {:reply, %{timeline: ^bootstrap}, ^socket} =
             TuistWeb.BuildRunLive.handle_event("load-timeline", %{"version" => version}, socket)

    assert {:reply, %{error: true}, ^socket} =
             TuistWeb.BuildRunLive.handle_event("load-timeline", %{"version" => version - 1}, socket)

    assert has_element?(lv, "#build-timeline[data-url$='/#{build.id}/timeline.json']")

    render_hook(lv, "load-timeline-step", %{
      request_id: 22,
      event_id: nil,
      direction: "last",
      search: ""
    })

    render_async(lv)
    assert_push_event(lv, "timeline-step", %{request_id: 22, step: %{event_id: 1}})

    render_hook(lv, "load-timeline-log", %{"event_id" => 1, "request_id" => 1, "build_run_id" => Ecto.UUID.generate()})
    render_async(lv)

    assert_push_event(lv, "timeline-log", %{
      request_id: 1,
      log: %{log: "EmitSwiftModule normal arm64\ncd /workspace", log_truncated: false}
    })

    assert {:reply, %{error: true}, ^socket} =
             TuistWeb.BuildRunLive.handle_event("load-timeline-log", %{"event_id" => -1}, socket)

    render_patch(
      lv,
      ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}?tab=timeline&latency-percentile=p90"
    )

    render_async(lv)
    assert has_element?(lv, "#build-timeline[data-version='#{version}']")
  end

  @tag :capture_log
  test "completion refresh loads new machine metrics and reopening reloads released metadata", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, status: "processing")
    path = ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}"
    {:ok, lv, _} = live(conn, path <> "?tab=timeline")
    render_async(lv)
    refute has_element?(lv, "#build-timeline")

    metric = %{
      timestamp: 1_700_000_000.25,
      offset_ms: 250.0,
      cpu_usage_percent: 42.0,
      memory_used_bytes: 8_000_000_000,
      memory_total_bytes: 16_000_000_000,
      network_bytes_in: 100,
      network_bytes_out: 200,
      disk_bytes_read: 300,
      disk_bytes_written: 400
    }

    {:ok, _} =
      RunsFixtures.build_fixture(
        id: build.id,
        project_id: project.id,
        inserted_at: build.inserted_at,
        machine_metrics: [metric]
      )

    render_async(lv)
    assert has_element?(lv, "#build-timeline")
    [version] = lv |> render() |> Floki.parse_document!() |> Floki.attribute("#build-timeline", "data-version")
    render_hook(lv, "load-timeline", %{version: String.to_integer(version)})
    assert has_element?(lv, "#build-timeline")

    render_patch(lv, path <> "?tab=overview")
    render_patch(lv, path <> "?tab=timeline")
    render_async(lv)
    [reopened] = lv |> render() |> Floki.parse_document!() |> Floki.attribute("#build-timeline", "data-version")
    assert String.to_integer(reopened) > String.to_integer(version)
    render_hook(lv, "load-timeline", %{version: String.to_integer(reopened)})
    assert has_element?(lv, "#build-timeline")
  end

  test "log loading stays asynchronous and superseded requests do not update the inspector", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)

    {:ok, lv, _} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}?tab=timeline")

    render_async(lv)
    owner = self()

    stub(Tuist.Builds, :build_step_log, fn _, id ->
      if id == 1 do
        send(owner, {:log_started, self()})

        receive do
          :release -> %{log: "Stale", log_truncated: false}
        end
      else
        %{log: "Latest", log_truncated: false}
      end
    end)

    render_hook(lv, "load-timeline-log", %{event_id: 1, request_id: 11})
    assert_receive {:log_started, task}
    monitor = Process.monitor(task)

    render_patch(
      lv,
      ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}?tab=timeline&latency-percentile=p90"
    )

    render_hook(lv, "load-timeline-log", %{event_id: 2, request_id: 12})
    assert_receive {:DOWN, ^monitor, :process, ^task, _}
    render_async(lv)
    assert_push_event(lv, "timeline-log", %{request_id: 12, log: %{log: "Latest", log_truncated: false}})
    refute_push_event(lv, "timeline-log", %{request_id: 11})
  end

  @tag :capture_log
  test "aligned machine samples join the timeline and old metric links still work", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    metric = %{
      timestamp: 1_700_000_000.25,
      offset_ms: 250.0,
      cpu_usage_percent: 42.0,
      memory_used_bytes: 8_000_000_000,
      memory_total_bytes: 16_000_000_000,
      network_bytes_in: 100,
      network_bytes_out: 200,
      disk_bytes_read: 300,
      disk_bytes_written: 400
    }

    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, machine_metrics: [metric])

    {:ok, lv, _} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}?tab=machine-metrics")

    render_async(lv)
    assert has_element?(lv, "#build-timeline")
    assert has_element?(lv, "[data-metric=cpu]")
    assert has_element?(lv, "[data-metric=memory]")
    refute has_element?(lv, "a", "Machine Metrics")
    assert has_element?(lv, "[data-part=empty][hidden]")
    refute has_element?(lv, "#build-timeline[data-machine-metrics]")
  end

  test "legacy machine samples keep the standalone metrics view", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    metric = %{
      timestamp: 1_700_000_000.25,
      cpu_usage_percent: 42.0,
      memory_used_bytes: 8_000_000_000,
      memory_total_bytes: 16_000_000_000,
      network_bytes_in: 100,
      network_bytes_out: 200,
      disk_bytes_read: 300,
      disk_bytes_written: 400
    }

    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, machine_metrics: [metric])

    {:ok, lv, _} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}?tab=machine-metrics")

    assert has_element?(lv, "a", "Machine Metrics")
    assert has_element?(lv, "#cpu-usage-chart")
    refute has_element?(lv, "#build-timeline")
  end

  test "timeline mounts without loading steps or analytics for other tabs", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        build_steps: [
          %{
            event_id: 1,
            title: "Compile",
            target: "App",
            project: "App",
            category: "swiftCompilation",
            start_ms: 0.0,
            duration_ms: 100.0,
            status: "success",
            log: "",
            log_truncated: false
          }
        ]
      )

    reject(Tuist.Builds, :build_timeline, 2)
    reject(Tuist.Builds, :list_build_files, 1)
    reject(Tuist.Builds, :list_build_targets, 1)
    reject(Tuist.Builds, :list_cacheable_tasks, 1)
    reject(Tuist.Builds, :list_cas_outputs, 1)
    reject(Tuist.Builds, :cas_output_metrics, 1)
    reject(Tuist.Builds, :cacheable_task_latency_metrics, 1)
    reject(CommandEvents, :module_cache_output_metrics, 1)

    {:ok, lv, _} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}?tab=timeline")

    render_async(lv)
    assert has_element?(lv, "#build-timeline")
    assert has_element?(lv, "[data-part=payload-loading]")
    assert has_element?(lv, "[data-part=empty][hidden]")
  end

  test "loads only the selected breakdown and cache subtab after leaving timeline", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        cacheable_tasks: [%{type: :swift, status: :hit_remote, key: "key"}]
      )

    path = ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build.id}"
    {:ok, lv, _} = live(conn, path <> "?tab=timeline")

    for {query, function} <- [
          {"?tab=overview&breakdown-tab=module", :list_build_targets},
          {"?tab=overview&breakdown-tab=file", :list_build_files},
          {"?tab=xcode-cache&cache-tab=cacheable-tasks", :list_cacheable_tasks},
          {"?tab=xcode-cache&cache-tab=cas-outputs", :list_cas_outputs}
        ] do
      test_pid = self()

      for name <- [:list_build_targets, :list_build_files, :list_cacheable_tasks, :list_cas_outputs] do
        stub(Tuist.Builds, name, fn options ->
          send(test_pid, {:loaded, name})
          Mimic.call_original(Tuist.Builds, name, [options])
        end)
      end

      render_patch(lv, path <> query)
      assert_receive {:loaded, ^function}
      refute_receive {:loaded, _}
    end
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
