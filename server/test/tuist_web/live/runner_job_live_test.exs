defmodule TuistWeb.RunnerJobLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Catalog
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.JobSteps
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-runner-job-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "renders metadata for a queued job", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_001,
        account_id: account.id,
        fleet_name: Catalog.pool_name(%{platform: :macos, xcode_version: "26.4"}),
        repository: "tuist/tuist",
        workflow_run_id: 310_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abcdef1234567890"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/310010/jobs/31001")

    assert html =~ "Server · Docker build"
    assert html =~ "tuist/tuist"
    assert html =~ "macOS"
    assert html =~ "Queued"
    # short_sha takes the first 7 chars
    assert html =~ "abcdef1"
  end

  test "renders timeline durations once a job has run", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_101,
        account_id: account.id,
        fleet_name: Catalog.pool_name(%{platform: :linux, vcpus: 4, memory_gb: 16}),
        repository: "tuist/cli",
        workflow_run_id: 311_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Unit Tests",
        head_branch: "main",
        head_sha: "1234567"
      })

    {:ok, candidate} =
      Jobs.pick_queued(Catalog.pool_name(%{platform: :linux, vcpus: 4, memory_gb: 16}), [])

    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_101, "tuist-runner-x")
    {:ok, _completed} = Jobs.complete(31_101, "success")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/311010/jobs/31101")

    assert html =~ "CLI · Unit Tests"
    assert html =~ "Linux"
    # status_badge_props maps conclusion=success → "Passed"
    assert html =~ "Passed"
  end

  test "surfaces linked build and test insights for the runner workflow run", %{
    conn: conn,
    account: account
  } do
    project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_301,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: 313_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Build and test",
        head_branch: "main",
        head_sha: "abcdef1234567890"
      })

    {:ok, build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: account.id,
        scheme: "App",
        duration: 120_000,
        inserted_at: ~N[2026-05-28 10:03:00.000000],
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        ci_run_id: "313010",
        cacheable_tasks_count: 4,
        cacheable_task_local_hits_count: 1,
        cacheable_task_remote_hits_count: 1
      )

    {:ok, second_build_run} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: account.id,
        scheme: "AppClip",
        duration: 60_000,
        inserted_at: ~N[2026-05-28 10:02:00.000000],
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        ci_run_id: "313010",
        cacheable_tasks_count: 2,
        cacheable_task_local_hits_count: 1,
        cacheable_task_remote_hits_count: 1
      )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "xcodebuild",
      is_ci: true,
      build_run_id: build_run.id,
      cacheable_targets: ["App", "Core", "UI", "Networking"],
      local_cache_target_hits: ["App"],
      remote_cache_target_hits: ["Core", "UI"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "xcodebuild",
      is_ci: true,
      build_run_id: second_build_run.id,
      cacheable_targets: ["AppClip", "AppClipCore"],
      local_cache_target_hits: ["AppClip"],
      remote_cache_target_hits: []
    )

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: account.id,
        scheme: "AppTests",
        duration: 90_000,
        ran_at: ~N[2026-05-28 10:03:15.000000],
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        ci_run_id: "313010"
      )

    {:ok, second_test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: account.id,
        scheme: "AppClipTests",
        duration: 30_000,
        ran_at: ~N[2026-05-28 10:02:15.000000],
        ci_provider: "github",
        ci_project_handle: "tuist/tuist",
        ci_run_id: "313010"
      )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "test",
      is_ci: true,
      test_run_id: test_run.id,
      test_targets: ["AppTests", "CoreTests", "UITests", "NetworkingTests"],
      local_test_target_hits: ["AppTests"],
      remote_test_target_hits: ["CoreTests", "UITests"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "test",
      is_ci: true,
      test_run_id: second_test_run.id,
      test_targets: ["AppClipTests", "AppClipUITests"],
      local_test_target_hits: ["AppClipTests"],
      remote_test_target_hits: []
    )

    step_started_at = ~U[2026-05-28 10:00:00.000000Z]
    step_completed_at = ~U[2026-05-28 10:03:30.000000Z]

    :ok =
      JobSteps.record([
        %{
          workflow_job_id: 31_301,
          account_id: account.id,
          number: 1,
          name: "Build and test",
          status: "completed",
          conclusion: "success",
          started_at: step_started_at,
          completed_at: step_completed_at
        }
      ])

    :ok =
      JobMetrics.record(31_301, account.id, [
        %{
          timestamp: DateTime.to_unix(step_started_at, :second) / 1,
          cpu_usage_percent: 55.0,
          memory_used_bytes: 8_000_000_000,
          memory_total_bytes: 16_000_000_000,
          network_bytes_in: 1_048_576,
          network_bytes_out: 524_288
        },
        %{
          timestamp: DateTime.to_unix(step_completed_at, :second) / 1,
          cpu_usage_percent: 80.0,
          memory_used_bytes: 10_000_000_000,
          memory_total_bytes: 16_000_000_000,
          network_bytes_in: 2_048_576,
          network_bytes_out: 1_524_288
        }
      ])

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/313010/jobs/31301")
    document = Floki.parse_fragment!(html)

    overview_html = document |> Floki.find("#runner-job-overview") |> Floki.raw_html()
    step_start_ms = step_started_at |> DateTime.to_unix(:millisecond) |> Integer.to_string()
    step_end_ms = step_completed_at |> DateTime.to_unix(:millisecond) |> Integer.to_string()

    index = fn needle ->
      case :binary.match(overview_html, needle) do
        {index, _length} -> index
        :nomatch -> flunk("Expected #{inspect(needle)} to be present in the runner overview")
      end
    end

    ci_details_index = index.(~s(data-part="ci-details"))
    summary_index = index.(~s(data-part="ci-details-section"))
    insights_card_index = index.(~s(data-part="insights-card"))
    insights_index = index.(~s(data-part="insights-grid"))
    metrics_card_index = index.(~s(data-part="overview-metrics-card"))
    metrics_index = index.(~s(data-part="overview"))
    steps_index = index.(~s(data-part="steps-card"))

    assert html =~ "Insights"
    assert html =~ "Builds"
    assert html =~ "Tests"
    assert html =~ "Metrics"
    assert ci_details_index < steps_index
    assert summary_index < insights_index
    assert summary_index < insights_card_index
    assert insights_card_index < metrics_card_index
    assert insights_index < metrics_index
    assert metrics_index < steps_index
    refute html =~ "Build runs"
    refute html =~ "Test runs"
    refute html =~ "Open builds"
    refute html =~ "Open tests"
    assert html =~ "App"
    assert html =~ "AppClip"
    assert html =~ "AppTests"
    assert html =~ "AppClipTests"
    assert html =~ "67%"
    assert html =~ "Module cache"
    assert html =~ "Selective testing"
    refute html =~ "4/6 hits"
    refute html =~ "Xcode cache 50%"
    refute html =~ "2 runs"

    build_chip =
      document
      |> Floki.find("a[data-part='step-insight-chip'][data-kind='build']")
      |> List.first()

    test_chip =
      document
      |> Floki.find("a[data-part='step-insight-chip'][data-kind='test']")
      |> List.first()

    assert build_chip
    assert test_chip

    assert build_chip |> Floki.find("[data-part='step-insight-chip-kind']") |> Floki.text() |> String.trim() ==
             "Build"

    assert build_chip |> Floki.find("[data-part='step-insight-chip-label']") |> Floki.text() |> String.trim() ==
             "App"

    assert test_chip |> Floki.find("[data-part='step-insight-chip-kind']") |> Floki.text() |> String.trim() ==
             "Test"

    assert test_chip |> Floki.find("[data-part='step-insight-chip-label']") |> Floki.text() |> String.trim() ==
             "AppTests"

    assert Floki.find(build_chip, "[data-part='step-insight-chip-status']") == []
    assert Floki.find(test_chip, "[data-part='step-insight-chip-status']") == []
    refute Floki.text(build_chip) =~ "Passed"
    refute Floki.text(test_chip) =~ "Passed"

    {"a", build_chip_attrs, _} = build_chip
    {"a", test_chip_attrs, _} = test_chip

    assert {"href", "/#{account.name}/tuist/builds/build-runs/#{build_run.id}"} in build_chip_attrs

    assert {"href", "/#{account.name}/tuist/tests/test-runs/#{test_run.id}"} in test_chip_attrs

    for {"a", attrs, _} <- Floki.find(document, "[data-part='insights-run-row']") do
      assert {"data-step-start", step_start_ms} in attrs
      assert {"data-step-end", step_end_ms} in attrs
    end

    lv |> element(~s{[data-part="step-header"][phx-value-number="1"]}) |> render_click()
    expanded = lv |> element(~s{[data-part="step-expanded"]}) |> render()

    refute expanded =~ ~s(data-part="step-insight-detail")
    assert expanded =~ "No logs were captured for this step."
  end

  test "renders the captured steps for a completed job", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_401,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: 314_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abcdef1"
      })

    {:ok, candidate} = Jobs.pick_queued("macos-xcode-26.4", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_401, "tuist-runner-x")

    {:ok, _completed} = Jobs.complete(31_401, "failure")

    :ok =
      JobSteps.record([
        %{
          workflow_job_id: 31_401,
          account_id: account.id,
          number: 1,
          name: "Set up job",
          status: "completed",
          conclusion: "success",
          started_at: ~U[2026-05-28 10:00:00.000000Z],
          completed_at: ~U[2026-05-28 10:00:05.000000Z]
        },
        %{
          workflow_job_id: 31_401,
          account_id: account.id,
          number: 2,
          name: "Run tests",
          status: "completed",
          conclusion: "failure",
          started_at: ~U[2026-05-28 10:00:05.000000Z],
          completed_at: ~U[2026-05-28 10:00:35.000000Z]
        }
      ])

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/314010/jobs/31401")

    assert html =~ "Steps"
    assert html =~ "Set up job"
    assert html =~ "Run tests"
    # 30-second duration badge for the failing step (no fractional seconds)
    assert html =~ "30s"
    refute html =~ "30.0s"
  end

  test "renders the steps empty state for a job without captured steps", %{
    conn: conn,
    account: account
  } do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_501,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/cli",
        workflow_run_id: 315_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Lint",
        head_branch: "main",
        head_sha: "1234567"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/315010/jobs/31501")

    assert html =~ "Steps will appear here once the job finishes."
  end

  test "renders captured logs on mount", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_601,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 316_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_601,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "compiling project"
        }
      ])

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/316010/jobs/31601")

    assert html =~ "Logs"
    assert html =~ "compiling project"
  end

  test "refreshes the Logs tab when FetchLogsWorker broadcasts :runner_job_logs_ready",
       %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_610,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 316_100,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/316100/jobs/31610?tab=logs")
    assert html =~ "No logs have been captured for this job yet."

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_610,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "after-broadcast line"
        }
      ])

    Tuist.PubSub.broadcast(
      %{workflow_job_id: 31_610},
      JobLogs.topic(31_610),
      :runner_job_logs_ready
    )

    html = render(lv)
    assert html =~ "after-broadcast line"
    refute html =~ "No logs have been captured for this job yet."
  end

  test "shows the Download logs button after ArchiveLogsWorker broadcasts :runner_job_log_archived",
       %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_620,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 316_200,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_620,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "hi"
        }
      ])

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/316200/jobs/31620?tab=logs")
    refute html =~ "Download logs"

    Tuist.PubSub.broadcast(
      %{workflow_job_id: 31_620, archived_at: DateTime.utc_now()},
      JobLogs.topic(31_620),
      :runner_job_log_archived
    )

    assert render(lv) =~ "Download logs"
  end

  test "expanding a step reveals only that step's logs", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_602,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 316_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_602, "runner-x")

    {:ok, _} = Jobs.complete(31_602, "success")

    # Three GH-shaped steps: an auto "Set up job" head, a single
    # user "Build" step delimited by `##[group]Run`, and an auto
    # "Complete job" tail anchored to its own `started_at`. Slicing
    # walks the marker, not the timestamps — see Tuist.Runners.JobLogs.
    :ok =
      JobSteps.record([
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          number: 1,
          name: "Set up job",
          status: "completed",
          conclusion: "success",
          started_at: ~U[2026-05-28 12:00:00.000000Z],
          completed_at: ~U[2026-05-28 12:00:00.000000Z]
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          number: 2,
          name: "Build",
          status: "completed",
          conclusion: "success",
          started_at: ~U[2026-05-28 12:00:30.000000Z],
          completed_at: ~U[2026-05-28 12:01:00.000000Z]
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          number: 3,
          name: "Complete job",
          status: "completed",
          conclusion: "success",
          started_at: ~U[2026-05-28 12:02:00.000000Z],
          completed_at: ~U[2026-05-28 12:02:00.000000Z]
        }
      ])

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "Current runner version"
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 2,
          ts: ~U[2026-05-28 12:00:30.000000Z],
          message: "##[group]Run build.sh"
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 3,
          ts: ~U[2026-05-28 12:00:30.000000Z],
          message: "##[endgroup]"
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 4,
          ts: ~U[2026-05-28 12:00:45.000000Z],
          message: "inside the build step"
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 5,
          ts: ~U[2026-05-28 12:02:00.000000Z],
          message: "after the build step"
        }
      ])

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/runs/316020/jobs/31602")

    # Expanding the Build step (number 2) shows the in-step lines
    # but not the teardown content.
    lv |> element(~s{[data-part="step-header"][phx-value-number="2"]}) |> render_click()
    panel = lv |> element(~s{[data-part="step-logs"]}) |> render()

    assert panel =~ "inside the build step"
    refute panel =~ "after the build step"
    refute panel =~ "Current runner version"
  end

  test "defaults to the Overview tab and selects Logs via ?tab=logs", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_701,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 317_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/runs/317010/jobs/31701")
    assert has_element?(lv, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Overview")
    refute has_element?(lv, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Logs")

    {:ok, lv2, _html} = live(conn, ~p"/#{account.name}/runners/runs/317010/jobs/31701?tab=logs")
    assert has_element?(lv2, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Logs")
    refute has_element?(lv2, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Overview")
  end

  test "renders the machine metrics charts on the Metrics tab", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_810,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 318_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Test",
        head_branch: "main",
        head_sha: "abc"
      })

    :ok =
      JobMetrics.record(31_810, account.id, [
        %{
          timestamp: 1_750_000_000.0,
          cpu_usage_percent: 70.0,
          cpu_iowait_percent: 3.0,
          memory_used_bytes: 8_000_000_000,
          memory_total_bytes: 16_000_000_000,
          network_bytes_in: 1_048_576,
          network_bytes_out: 524_288,
          disk_used_bytes: 40_000_000_000,
          disk_total_bytes: 64_000_000_000
        }
      ])

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/318010/jobs/31810?tab=metrics")

    assert html =~ "CPU I/O Wait"
    assert html =~ "Storage"
    assert html =~ "runner-job-metrics-cpu"
  end

  test "shows the metrics empty state when a job has no samples", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_820,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 318_020,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Test",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/318020/jobs/31820?tab=metrics")

    assert html =~ "Machine metrics will appear here"
    refute html =~ "runner-job-metrics-cpu"
  end

  test "loads only the tail and pages older logs on demand", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_801,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 318_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    # More than one page (page size is 200), so the oldest line is not
    # in the initial tail.
    :ok =
      JobLogs.append(
        for n <- 1..250 do
          %{
            workflow_job_id: 31_801,
            account_id: account.id,
            line_number: n,
            ts: DateTime.add(~U[2026-05-28 12:00:00.000000Z], n, :second),
            message: if(n == 1, do: "FIRST_LINE_MARKER", else: "line #{n}")
          }
        end
      )

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/318010/jobs/31801?tab=logs")

    refute html =~ "FIRST_LINE_MARKER"
    assert has_element?(lv, ~s{[phx-click="load_older"]})

    html_after = lv |> element(~s{[phx-click="load_older"]}) |> render_click()

    assert html_after =~ "FIRST_LINE_MARKER"
    refute has_element?(lv, ~s{[phx-click="load_older"]})
  end

  test "searches the full log, including lines outside the loaded tail", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_901,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 319_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    # 250 lines (> page size). The match is on line 1, which is NOT in
    # the initially-loaded tail — search must hit the server.
    :ok =
      JobLogs.append(
        for n <- 1..250 do
          %{
            workflow_job_id: 31_901,
            account_id: account.id,
            line_number: n,
            ts: DateTime.add(~U[2026-05-28 12:00:00.000000Z], n, :second),
            message: if(n == 1, do: "DEEP_MATCH_TOKEN", else: "line #{n}")
          }
        end
      )

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/319010/jobs/31901?tab=logs")

    refute html =~ "DEEP_MATCH_TOKEN"

    results =
      lv
      |> form(~s{[data-part="logs-search-form"]}, %{search: "DEEP_MATCH_TOKEN"})
      |> render_change()

    assert results =~ "DEEP_MATCH_TOKEN"

    scoped = lv |> element("#runner-log-search-results") |> render()
    assert scoped =~ "DEEP_MATCH_TOKEN"
    refute scoped =~ "line 200"
  end

  test "toggles timestamp visibility", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_902,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 319_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_902,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "a line"
        }
      ])

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/319020/jobs/31902?tab=logs")
    # Hidden by default; the icon points to the action (show) — a plain
    # hourglass, so the hourglass-off variant is absent.
    assert html =~ ~s(data-show-timestamps="false")
    assert html =~ "Timestamps"
    refute html =~ "icon-tabler-hourglass-off"

    toggled = lv |> element("#logs-timestamps-button") |> render_click()
    # Now visible; the action becomes "hide", so the icon is hourglass-off.
    assert toggled =~ ~s(data-show-timestamps="true")
    assert toggled =~ "icon-tabler-hourglass-off"
  end

  test "the Steps card also has a timestamps button toggling per-step timestamps", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_950,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 319_500,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_950, "runner-x")

    {:ok, _} = Jobs.complete(31_950, "success")

    :ok =
      JobSteps.record([
        %{
          workflow_job_id: 31_950,
          account_id: account.id,
          number: 1,
          name: "Build",
          status: "completed",
          conclusion: "success",
          started_at: ~U[2026-05-28 12:00:00.000000Z],
          completed_at: ~U[2026-05-28 12:01:00.000000Z]
        }
      ])

    # Overview tab is the default, where the Steps card lives.
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/319500/jobs/31950")

    assert has_element?(lv, "#steps-timestamps-button")
    assert html =~ ~s(data-show-timestamps="false")

    toggled = lv |> element("#steps-timestamps-button") |> render_click()
    assert toggled =~ ~s(data-show-timestamps="true")
  end

  test "raises 404 when the workflow_job_id belongs to another account", %{
    conn: conn,
    account: account
  } do
    other = AccountsFixtures.user_fixture().account

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_201,
        account_id: other.id,
        fleet_name: "fleet-x",
        repository: "evil/corp",
        workflow_run_id: 312_010,
        workflow_name: "Evil",
        run_attempt: 1,
        job_name: "hidden",
        head_branch: "main",
        head_sha: "dead"
      })

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/runs/312010/jobs/31201")
    end
  end

  test "raises 404 when the workflow_run_id in the URL doesn't match the job's run", %{
    conn: conn,
    account: account
  } do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_301,
        account_id: account.id,
        fleet_name: "fleet-y",
        repository: "tuist/tuist",
        workflow_run_id: 313_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef"
      })

    assert_raise NotFoundError, fn ->
      # Job exists under run 313010, URL claims 999999 — 404 the
      # same way GitHub would.
      live(conn, ~p"/#{account.name}/runners/runs/999999/jobs/31301")
    end
  end

  test "raises 404 for a non-integer workflow_job_id", %{conn: conn, account: account} do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/runs/312010/jobs/notanumber")
    end
  end

  describe "step_window/1" do
    test "spans the first step's start to the last step's end in epoch ms" do
      steps = [
        %{started_at: ~U[2026-05-28 10:00:00Z], completed_at: ~U[2026-05-28 10:00:05Z]},
        %{started_at: ~U[2026-05-28 10:00:05Z], completed_at: ~U[2026-05-28 10:01:00Z]}
      ]

      assert TuistWeb.RunnerJobLive.step_window(steps) == %{
               min: DateTime.to_unix(~U[2026-05-28 10:00:00Z], :millisecond),
               max: DateTime.to_unix(~U[2026-05-28 10:01:00Z], :millisecond)
             }
    end

    test "returns nil when there are no steps with timestamps" do
      assert TuistWeb.RunnerJobLive.step_window([]) == nil
      assert TuistWeb.RunnerJobLive.step_window([%{started_at: nil, completed_at: nil}]) == nil
    end
  end
end
