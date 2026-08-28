defmodule TuistWeb.BazelInvocationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "bazeluser#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "bazel-org",
        creator: user,
        preload: [:account]
      )

    project =
      ProjectsFixtures.project_fixture(
        name: "bazel-project",
        account_id: account.id,
        build_system: :bazel,
        vcs_connection: [repository_full_handle: "tuist/bazel-telemetry-demo"]
      )

    conn =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, organization: organization, project: project}
  end

  test "renders completed invocations and correlated cache totals", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    create_invocation(project)
    create_cache_event(project)

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2100-01-01T00:00:00Z"
    }

    path = ~p"/#{organization.account.name}/#{project.name}/invocations" <> "?" <> URI.encode_query(params)
    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-invocations")
    assert has_element?(live_view, "#bazel-total-invocations", "1")
    assert has_element?(live_view, "#bazel-success-rate", "100.0%")
    assert has_element?(live_view, "#bazel-invocations-table", "test")
    assert has_element?(live_view, "#bazel-invocations-table", "Command")
    assert has_element?(live_view, "#bazel-invocations-table", "//App:App")
    assert has_element?(live_view, "#bazel-invocations-table", "100.0%")
    assert has_element?(live_view, "#bazel-invocations-table", "Downloaded")
    assert has_element?(live_view, "#bazel-invocations-table", "Uploaded")
    assert has_element?(live_view, "#bazel-invocations-table", "2.0 KB")

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-invocation-duration")

    live_view
    |> element("[phx-value-widget='total-builds']")
    |> render_click()

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-total-invocations")
    assert has_element?(live_view, "#bazel-builds-analytics-chart")
  end

  test "shows only build invocations on the Bazel builds page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "build-invocation", "build", finished_at),
      invocation_attributes(project, "test-invocation", "test", finished_at),
      invocation_attributes(project, "run-invocation", "run", finished_at)
    ])

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2100-01-01T00:00:00Z"
    }

    path = ~p"/#{organization.account.name}/#{project.name}/builds" <> "?" <> URI.encode_query(params)
    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-invocations", "Builds")
    assert has_element?(live_view, "#bazel-total-invocations", "1")
    assert has_element?(live_view, "#bazel-invocations-table", "//App:App")
    refute has_element?(live_view, "#bazel-invocations-table", "test")
    refute has_element?(live_view, "#bazel-invocations-table", "run")
    refute has_element?(live_view, "#bazel-invocations-table", "Command")
    refute has_element?(live_view, "#bazel-invocations-sort-by")
  end

  test "renders a build invocation detail from the builds page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "BUILD-INVOCATION", "build", finished_at)
    ])

    {:ok, invocation} = Bazel.get_invocation(project.id, "BUILD-INVOCATION")
    assert invocation.critical_path_duration_ms == 8_000

    assert invocation.critical_path_action_descriptions == [
             "action 'Compiling Sources/App/main.swift'",
             "action 'Linking //App:App'"
           ]

    ReapiCache.create_cache_events([
      cache_event_attributes(project, "build-invocation"),
      content_cache_event_attributes(project, "build-invocation")
    ])

    Bazel.create_invocation_logs([
      %{
        invocation_id: "BUILD-INVOCATION",
        sequence_number: 1,
        stream: "stdout",
        message: "Build complete\n",
        project_id: project.id,
        observed_at: finished_at
      }
    ])

    {:ok, live_view, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/invocations/BUILD-INVOCATION")

    assert has_element?(live_view, "#bazel-invocation", "build")
    assert has_element?(live_view, "#bazel-invocation", "Details")
    assert has_element?(live_view, "[data-part='header'] [data-part='label']", "//App:App")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Succeeded")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Remote services")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Mode")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Environment")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "macOS · arm64")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Repository")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "main")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "1d7b1f4f6053")
    assert has_element?(live_view, "#bazel-invocation", "Critical path")
    assert has_element?(live_view, "#bazel-invocation", "Metrics")
    assert has_element?(live_view, "#bazel-invocation", "Details")
    assert has_element?(live_view, "#bazel-invocation", "Timeline")
    assert has_element?(live_view, "#bazel-build-timeline", "")
    assert has_element?(live_view, "#bazel-processor-time", "15.5s")
    assert has_element?(live_view, "#bazel-actions-executed", "89")
    assert has_element?(live_view, "#bazel-targets", "42 / 3,964")
    assert has_element?(live_view, "#bazel-packages-loaded", "160")
    assert has_element?(live_view, "[data-part='critical-path-section']", "Minimum completion time")
    assert has_element?(live_view, "[data-part='critical-path-section']", "Compiling Sources/App/main.swift")

    assert has_element?(
             live_view,
             "a[data-part='source-file'][href='https://github.com/tuist/bazel-telemetry-demo/blob/1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f/Sources/App/main.swift']"
           )

    assert has_element?(live_view, "[data-part='critical-path-timeline']")
    assert has_element?(live_view, "[data-part='critical-path-timeline'] [data-tone='information']")

    assert has_element?(live_view, "[data-part='critical-path-action'][data-tone='information'][data-highlighted]")

    assert has_element?(live_view, "[data-part='tabs']", "Overview")
    assert has_element?(live_view, "[data-part='tabs']", "Command")
    assert has_element?(live_view, "[data-part='tabs']", "Cache")
    assert has_element?(live_view, "[data-part='tabs']", "Logs")
    assert has_element?(live_view, "[data-part='actions']", "Download logs")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds/invocations/BUILD-INVOCATION?tab=command"
    )

    assert has_element?(live_view, "#bazel-command-configuration", "bazel build //App:App")
    assert has_element?(live_view, "#bazel-command-configuration", "Bazel version")
    assert has_element?(live_view, "#bazel-command-configuration", "remote-cache")
    assert has_element?(live_view, "#bazel-requested-command-copy")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds/invocations/BUILD-INVOCATION?tab=cache"
    )

    assert has_element?(live_view, "#bazel-invocation", "Summary")
    assert has_element?(live_view, "#bazel-invocation-cache-requests", "2")
    assert has_element?(live_view, "#bazel-invocation-cache-hits", "100.0%")
    assert has_element?(live_view, "#bazel-invocation-cache-misses", "0.0%")
    assert has_element?(live_view, "#bazel-invocation-cache-writes", "0.0%")
    assert has_element?(live_view, "#bazel-invocation-cache-events-table thead th:first-child", "Action")
    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "SwiftCompile")
    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "Content object")
    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "Content-addressable storage")
    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "cas-digest-1…")
    assert has_element?(live_view, "#bazel-invocation-cache-requests-timeline")
    assert has_element?(live_view, "#bazel-invocation-cache-filter-dropdown")
    assert has_element?(live_view, "#bazel-invocation-cache-search")

    render_click(live_view, "add_filter", %{"value" => "operation"})

    assert has_element?(live_view, "#operation", "Cache")

    render_click(live_view, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "operation",
      "value" => "cas"
    })

    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "Content object")
    refute has_element?(live_view, "#bazel-invocation-cache-events-table", "SwiftCompile")

    render_click(live_view, "add_filter", %{"value" => "outcome"})

    assert has_element?(live_view, "#outcome", "Outcome")

    render_click(live_view, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "outcome",
      "value" => "miss"
    })

    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "No matching cache requests")

    live_view
    |> element("#bazel-invocation-cache-search-form")
    |> render_change(%{"search" => "no-match"})

    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "No matching cache requests")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds/invocations/BUILD-INVOCATION?tab=logs"
    )

    assert has_element?(live_view, "[data-part='log-output']", "Build complete")
    assert has_element?(live_view, "[data-part='back-button']", "Builds")
  end

  test "uses the standard empty state when an invocation has no cache requests", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "NO-CACHE-INVOCATION", "build", finished_at)
    ])

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/invocations/NO-CACHE-INVOCATION?tab=cache"
      )

    assert has_element?(
             live_view,
             "[data-part='empty-cache-requests-card-section'][data-empty]",
             "No cache requests"
           )

    refute has_element?(live_view, "#bazel-invocation-cache-search")
    refute has_element?(live_view, "#bazel-invocation-cache-filter-dropdown")
  end

  test "renders Bazel cache analytics and cache activity", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "cache-invocation", "build", finished_at)
    ])

    ReapiCache.create_cache_events([
      cache_event_attributes(project, "cache-invocation")
    ])

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2100-01-01T00:00:00Z"
    }

    path = ~p"/#{organization.account.name}/#{project.name}/bazel-cache" <> "?" <> URI.encode_query(params)
    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-cache")
    assert has_element?(live_view, "#bazel-cache-hit-rate", "100.0%")
    assert has_element?(live_view, "#bazel-cache-events-table", "SwiftCompile")
    assert has_element?(live_view, "#bazel-cache-invocations-table", "build")
    assert has_element?(live_view, "#bazel-cache-invocations-table", "//App:App")
    assert has_element?(live_view, "[data-part='bazel-cache-invocations-card']", "Invocations using cache")
    assert has_element?(live_view, "[data-part='bazel-cache-activity-card']", "Action cache activity")
    assert has_element?(live_view, "#bazel-cache-invocations-hit-rate-chart")
    assert has_element?(live_view, "#bazel-cache-filter-dropdown")
    refute has_element?(live_view, "#bazel-cache-sort-by")

    live_view
    |> element("[phx-value-widget='cache_transfer']")
    |> render_click()

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-cache-transfer")
    assert has_element?(live_view, "#bazel-cache-analytics-chart")
  end

  test "calculates action-cache transfer, latency, and throughput from Kura observations", %{
    project: project
  } do
    ReapiCache.create_cache_events([
      cache_event_attributes(project, "cache-metrics"),
      project
      |> cache_event_attributes("cache-metrics")
      |> Map.merge(%{outcome: "miss", size: 0, duration_ms: 5}),
      project
      |> cache_event_attributes("cache-metrics")
      |> Map.merge(%{outcome: "write", size: 1024, duration_ms: 20})
    ])

    summary = ReapiCache.summary(project.id)

    assert summary.transfer_bytes == 3072
    assert summary.read_latency_ms == 7.5
    assert summary.write_latency_ms == 20.0
    assert summary.latency_ms == 35 / 3
    assert summary.download_throughput_bytes_per_second == 204_800.0
    assert summary.upload_throughput_bytes_per_second == 51_200.0
    assert summary.throughput_bytes_per_second == 102_400.0
  end

  defp create_invocation(project) do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([invocation_attributes(project, "invocation-1", "test", finished_at)])
  end

  defp invocation_attributes(project, invocation_id, command, finished_at) do
    %{
      invocation_id: invocation_id,
      command: command,
      target_patterns: ["//App:App"],
      bazel_version: "8.1.0",
      client_platform: "macos_arm64",
      git_branch: "main",
      git_commit_sha: "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f",
      configurations: ["ci", "remote-cache"],
      compilation_mode: "opt",
      remote_cache_enabled: true,
      remote_execution_enabled: true,
      cpu_time_ms: 15_503,
      actions_executed: 89,
      targets_loaded: 42,
      targets_configured: 3_964,
      packages_loaded: 160,
      build_timeline_duration_ms: 8_000,
      build_timeline_lanes: ["Critical path", "Worker 1"],
      build_timeline_span_lanes: [0, 1],
      build_timeline_span_start_ms: [0, 1_000],
      build_timeline_span_durations_ms: [6_000, 2_000],
      build_timeline_span_categories: ["critical_path", "execution"],
      build_timeline_span_descriptions: ["action 'Compiling Sources/App/main.swift'", "Action cache check"],
      status: "success",
      exit_code: 0,
      started_at: NaiveDateTime.add(finished_at, -15, :second),
      finished_at: finished_at,
      duration_ms: 15_000,
      critical_path_duration_ms: 8_000,
      critical_path_action_descriptions: [
        "action 'Compiling Sources/App/main.swift'",
        "action 'Linking //App:App'"
      ],
      critical_path_action_durations_ms: [6_000, 2_000],
      project_id: project.id,
      account_handle: project.account.name,
      project_handle: project.name,
      cache_endpoint: "cache.tuist.dev"
    }
  end

  defp create_cache_event(project) do
    ReapiCache.create_cache_events([
      cache_event_attributes(project, "invocation-1"),
      content_cache_event_attributes(project, "invocation-1")
    ])
  end

  defp cache_event_attributes(project, invocation_id) do
    %{
      client_kind: "bazel",
      operation: "action_cache",
      outcome: "hit",
      action_digest: "action-hit",
      size: 2048,
      duration_ms: 10,
      invocation_id: invocation_id,
      action_mnemonic: "SwiftCompile",
      target_label: "//App:App",
      configuration_id: "config-1",
      project_id: project.id,
      account_handle: project.account.name,
      project_handle: project.name,
      cache_endpoint: "cache.tuist.dev"
    }
  end

  defp content_cache_event_attributes(project, invocation_id) do
    %{
      client_kind: "bazel",
      operation: "cas",
      outcome: "hit",
      action_digest: "cas-digest-1234567890",
      size: 4_096,
      duration_ms: 14,
      invocation_id: invocation_id,
      action_mnemonic: "",
      target_label: "",
      configuration_id: "",
      project_id: project.id,
      account_handle: project.account.name,
      project_handle: project.name,
      cache_endpoint: "cache.tuist.dev"
    }
  end
end
