defmodule TuistWeb.BazelInvocationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache
  alias Tuist.ReapiCache.CacheEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

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
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Bazel.create_invocations([invocation_attributes(project, "invocation-1", "build", finished_at)])
    create_cache_event(project)

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2100-01-01T00:00:00Z"
    }

    path = ~p"/#{organization.account.name}/#{project.name}/builds" <> "?" <> URI.encode_query(params)
    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-invocations")
    assert has_element?(live_view, "#bazel-total-invocations", "1")
    assert has_element?(live_view, "#bazel-success-rate", "100.0%")
    assert has_element?(live_view, "#bazel-invocations-table", "Succeeded")
    refute has_element?(live_view, "#bazel-invocations-table", "Command")
    assert has_element?(live_view, "#bazel-invocations-table", "//App:App")
    assert has_element?(live_view, "#bazel-invocations-table", "100.0%")
    assert has_element?(live_view, "#bazel-invocations-table", "Downloaded")
    assert has_element?(live_view, "#bazel-invocations-table", "Uploaded")
    assert has_element?(live_view, "#bazel-invocations-table", "6.1 KB")
    refute has_element?(live_view, "#bazel-invocations-filter-dropdown", "Command")

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-invocation-duration")

    live_view
    |> element("[phx-value-widget='total-builds']")
    |> render_click()

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-total-invocations")
    assert has_element?(live_view, "#bazel-builds-analytics-chart")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2100-01-01T00%3A00%3A00Z&invocations-sort-by=status&invocations-sort-order=asc"
    )

    assert has_element?(live_view, "#bazel-invocations-table", "Succeeded")
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

  test "sorts the build table by the selected column", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    succeeded =
      project
      |> invocation_attributes("succeeded-build", "build", finished_at)
      |> Map.merge(%{target_patterns: ["//App:Succeeded"], duration_ms: 100})

    failed =
      project
      |> invocation_attributes("failed-build", "build", NaiveDateTime.add(finished_at, -1, :second))
      |> Map.merge(%{target_patterns: ["//App:Failed"], status: "failure", exit_code: 1, duration_ms: 200})

    Bazel.create_invocations([succeeded, failed])

    path =
      ~p"/#{organization.account.name}/#{project.name}/builds?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2100-01-01T00%3A00%3A00Z&invocations-sort-by=status&invocations-sort-order=desc"

    {:ok, live_view, _html} = live(conn, path)

    assert has_element?(live_view, "#bazel-invocations-table tbody tr:first-child", "//App:Failed")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2100-01-01T00%3A00%3A00Z&invocations-sort-by=duration&invocations-sort-order=asc"
    )

    assert has_element?(live_view, "#bazel-invocations-table tbody tr:first-child", "//App:Succeeded")
  end

  test "bounds the build table to the selected analytics period", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Bazel.create_invocations([invocation_attributes(project, "outside-period", "build", finished_at)])

    path =
      ~p"/#{organization.account.name}/#{project.name}/builds?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2001-01-01T00%3A00%3A00Z"

    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    refute has_element?(live_view, "#bazel-invocations-table", "//App:App")

    assert has_element?(
             live_view,
             "[data-part='empty-bazel-invocations-card-section']",
             "No Bazel builds in the selected period."
           )

    refute has_element?(live_view, "[data-part='empty-bazel-invocations-card-section']", "Get started")
    assert has_element?(live_view, "[data-part='analytics-card-chart-section']", "No Bazel invocations in this period")
  end

  test "renders zero-valued invocation analytics when builds exist", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Bazel.create_invocations([invocation_attributes(project, "successful-build", "build", finished_at)])

    path =
      ~p"/#{organization.account.name}/#{project.name}/builds?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2100-01-01T00%3A00%3A00Z&analytics-selected-widget=failed-builds"

    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-builds-analytics-chart")
    refute has_element?(live_view, "[data-part='analytics-card-chart-section']", "No Bazel invocations in this period")
  end

  test "redirects the legacy invocation list to builds", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.name}/#{project.name}/invocations")

    assert redirected_to(conn, :moved_permanently) ==
             ~p"/#{organization.account.name}/#{project.name}/builds"
  end

  test "renders an invocation from the legacy detail route", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Bazel.create_invocations([invocation_attributes(project, "legacy-invocation", "build", finished_at)])

    {:ok, live_view, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/invocations/legacy-invocation")

    assert has_element?(live_view, "#bazel-invocation", "legacy-invocation")
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
      cache_event_attributes(project, "BUILD-INVOCATION"),
      content_cache_event_attributes(project, "BUILD-INVOCATION")
    ])

    cache_timeline =
      ReapiCache.invocation_cache_timeline(project.id, "BUILD-INVOCATION", limit: 1)

    assert length(cache_timeline.events) == 1
    assert cache_timeline.truncated?

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
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Remote cache")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Repository")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "main")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "1d7b1f4f6053")
    assert has_element?(live_view, "#bazel-invocation", "Critical path")
    assert has_element?(live_view, "#bazel-invocation", "Metrics")
    assert has_element?(live_view, "#bazel-invocation", "Details")
    assert has_element?(live_view, "#bazel-invocation", "Timeline")
    assert has_element?(live_view, "#bazel-build-timeline", "")
    assert render(live_view) =~ "&quot;value&quot;:[1,1000,3000]"
    assert render(live_view) =~ "&quot;durationLabel&quot;:&quot;Duration&quot;"
    assert render(live_view) =~ "&quot;startLabel&quot;:&quot;Started after&quot;"
    assert has_element?(live_view, "#bazel-processor-time", "15.5s")
    assert has_element?(live_view, "#bazel-actions-created", "481")
    assert has_element?(live_view, "#bazel-actions-executed", "89")
    assert has_element?(live_view, "#bazel-packages-loaded", "160")
    assert has_element?(live_view, "[data-part='critical-path-section']", "Minimum completion time")
    assert has_element?(live_view, "[data-part='critical-path-section']", "Compiling Sources/App/main.swift")

    assert has_element?(
             live_view,
             "a[data-part='source-file'][href='https://github.com/tuist/bazel-telemetry-demo/blob/1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f/Sources/App/main.swift']"
           )

    assert has_element?(live_view, "[data-part='critical-path-timeline'][role='img']")
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

    live_view
    |> element("#bazel-invocation-cache-search-form")
    |> render_change(%{"search" => "swiftcompile"})

    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "SwiftCompile")

    live_view
    |> element("#bazel-invocation-cache-search-form")
    |> render_change(%{"search" => ""})

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds/invocations/BUILD-INVOCATION?tab=cache&cache-sort-by=outcome&cache-sort-order=asc"
    )

    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "SwiftCompile")

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
             "This invocation did not use a remote cache."
           )

    refute has_element?(live_view, "#bazel-invocation-cache-search")
    refute has_element?(live_view, "#bazel-invocation-cache-filter-dropdown")
  end

  test "paginates every invocation log", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "LOGGED-INVOCATION", "test", finished_at)
    ])

    Bazel.create_invocation_logs(
      Enum.map(1..40, fn sequence_number ->
        %{
          invocation_id: "LOGGED-INVOCATION",
          sequence_number: sequence_number,
          stream: "stdout",
          message: "log #{sequence_number}\n",
          project_id: project.id,
          observed_at: finished_at
        }
      end)
    )

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/invocations/LOGGED-INVOCATION?tab=logs"
      )

    assert has_element?(live_view, "[data-part='log-output']", "log 1")
    refute has_element?(live_view, "[data-part='log-output']", "log 21")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/builds/invocations/LOGGED-INVOCATION?tab=logs&logs-page=2"
    )

    assert has_element?(live_view, "[data-part='log-output']", "log 21")
    assert has_element?(live_view, "[data-part='log-output']", "log 40")
  end

  test "discloses when the cache activity chart is capped", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "LARGE-CACHE-INVOCATION", "build", finished_at)
    ])

    ReapiCache.create_cache_events(
      Enum.map(1..501, fn index ->
        project
        |> cache_event_attributes("LARGE-CACHE-INVOCATION")
        |> Map.put(:action_digest, "action-#{index}")
      end)
    )

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/invocations/LARGE-CACHE-INVOCATION?tab=cache"
      )

    assert has_element?(
             live_view,
             "[data-part='cache-requests-timeline-limit']",
             "The chart shows the first 500 requests"
           )
  end

  test "bounds invocation cache requests to their ingest window", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "BOUNDED-CACHE-INVOCATION", "build", finished_at)
    ])

    old_inserted_at = NaiveDateTime.add(finished_at, -2, :day)

    event =
      project
      |> cache_event_attributes("BOUNDED-CACHE-INVOCATION")
      |> Map.merge(%{
        id: UUIDv7.generate(),
        action_mnemonic: "OldAction",
        inserted_at: old_inserted_at,
        observed_at: %{DateTime.from_naive!(old_inserted_at, "Etc/UTC") | microsecond: {0, 6}}
      })

    IngestRepo.insert_all(CacheEvent, [event])

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/invocations/BOUNDED-CACHE-INVOCATION?tab=cache"
      )

    assert has_element?(live_view, "[data-part='empty-cache-requests-card-section']")
    refute has_element?(live_view, "#bazel-invocation", "OldAction")
  end

  test "uses the same bounded ingest window for invocation cache summaries and requests", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      invocation_attributes(project, "DELAYED-CACHE-INVOCATION", "build", finished_at)
    ])

    delayed_inserted_at = NaiveDateTime.add(finished_at, 1, :hour)

    event =
      project
      |> cache_event_attributes("DELAYED-CACHE-INVOCATION")
      |> Map.merge(%{
        id: UUIDv7.generate(),
        action_mnemonic: "DelayedAction",
        inserted_at: delayed_inserted_at,
        observed_at: %{DateTime.from_naive!(delayed_inserted_at, "Etc/UTC") | microsecond: {0, 6}}
      })

    IngestRepo.insert_all(CacheEvent, [event])

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/invocations/DELAYED-CACHE-INVOCATION?tab=cache"
      )

    assert has_element?(live_view, "#bazel-invocation-cache-events-table", "DelayedAction")
  end

  test "does not advertise invocation logs outside the bounded observation window", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Bazel.create_invocations([invocation_attributes(project, "SKEWED-LOG-INVOCATION", "build", finished_at)])

    Bazel.create_invocation_logs([
      %{
        invocation_id: "SKEWED-LOG-INVOCATION",
        sequence_number: 1,
        stream: "stdout",
        message: "outside the invocation window",
        project_id: project.id,
        observed_at: NaiveDateTime.add(finished_at, -2, :day)
      }
    ])

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/invocations/SKEWED-LOG-INVOCATION?tab=logs"
      )

    refute has_element?(live_view, "[data-part='actions']", "Download logs")
    assert has_element?(live_view, "[data-part='empty-logs']")
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
    assert has_element?(live_view, "#bazel-cache-events-table thead", "Received")
    assert has_element?(live_view, "#bazel-cache-invocations-table", "build")
    assert has_element?(live_view, "#bazel-cache-invocations-table", "//App:App")
    assert has_element?(live_view, "[data-part='bazel-cache-invocations-card']", "Invocations using cache")
    assert has_element?(live_view, "[data-part='bazel-cache-activity-card']", "Remote cache activity")
    assert has_element?(live_view, "#bazel-cache-invocations-hit-rate-chart")
    assert has_element?(live_view, "#bazel-cache-filter-dropdown")
    refute has_element?(live_view, "#bazel-cache-sort-by")

    live_view
    |> element("[phx-value-widget='cache_transfer']")
    |> render_click()

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-cache-transfer")
    assert has_element?(live_view, "#bazel-cache-analytics-chart")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/bazel-cache?#{Map.merge(params, %{"cache-sort-by" => "target", "cache-sort-order" => "asc"})}"
    )

    assert has_element?(live_view, "#bazel-cache-events-table", "SwiftCompile")

    render_click(live_view, "add_filter", %{"value" => "target"})

    assert has_element?(live_view, "#target", "Target")
  end

  test "bounds cache activity to the selected analytics period", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    ReapiCache.create_cache_events([
      cache_event_attributes(project, "outside-selected-period")
    ])

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2001-01-01T00:00:00Z"
    }

    path = ~p"/#{organization.account.name}/#{project.name}/bazel-cache" <> "?" <> URI.encode_query(params)
    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(
             live_view,
             "[data-part='bazel-cache-activity-card']",
             "No cache observations in the selected period"
           )

    refute has_element?(live_view, "#bazel-cache-events-table")
    refute has_element?(live_view, "[data-part='bazel-cache-activity-card']", "SwiftCompile")
  end

  test "renders filtered empty states without onboarding copy", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Bazel.create_invocations([invocation_attributes(project, "filtered-build", "build", finished_at)])
    ReapiCache.create_cache_events([cache_event_attributes(project, "filtered-build")])

    date_params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2100-01-01T00:00:00Z"
    }

    builds_path = ~p"/#{organization.account.name}/#{project.name}/builds" <> "?" <> URI.encode_query(date_params)
    {:ok, builds_live, _html} = live(conn, builds_path)
    render_click(builds_live, "add_filter", %{"value" => "status"})

    render_click(builds_live, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "status",
      "value" => "failure"
    })

    assert has_element?(
             builds_live,
             "[data-part='empty-bazel-invocations-card-section']",
             "No Bazel builds match the current filters."
           )

    refute has_element?(builds_live, "[data-part='empty-bazel-invocations-card-section']", "Get started")

    cache_path =
      ~p"/#{organization.account.name}/#{project.name}/bazel-cache" <> "?" <> URI.encode_query(date_params)

    {:ok, cache_live, _html} = live(conn, cache_path)
    render_async(cache_live, @render_async_timeout)
    render_click(cache_live, "add_filter", %{"value" => "outcome"})

    render_click(cache_live, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "outcome",
      "value" => "miss"
    })

    assert has_element?(
             cache_live,
             "[data-part='bazel-cache-activity-card']",
             "No cache observations match the current filters."
           )

    refute has_element?(cache_live, "[data-part='bazel-cache-activity-card']", "Get started")
  end

  test "falls back to average for an invalid cache percentile", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    ReapiCache.create_cache_events([cache_event_attributes(project, "cache-percentile")])

    path =
      ~p"/#{organization.account.name}/#{project.name}/bazel-cache?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2100-01-01T00%3A00%3A00Z&hit-rate-type=untrusted-value"

    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-cache-hit-rate", "Avg. action cache hit rate")
    assert has_element?(live_view, "#bazel-cache-hit-rate", "100.0%")
  end

  test "renders a zero-percent cache hit-rate series when lookups exist", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    miss = project |> cache_event_attributes("all-misses") |> Map.put(:outcome, "miss")
    ReapiCache.create_cache_events([miss])

    path =
      ~p"/#{organization.account.name}/#{project.name}/bazel-cache?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2100-01-01T00%3A00%3A00Z"

    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-cache-hit-rate", "0.0%")
    assert has_element?(live_view, "#bazel-cache-analytics-chart")
    refute has_element?(live_view, "[data-part='analytics-card-chart-section']", "No cache observations yet")
  end

  test "calculates remote-cache transfer, latency, and throughput from Kura observations", %{
    project: project
  } do
    ReapiCache.create_cache_events([
      cache_event_attributes(project, "cache-metrics"),
      project
      |> cache_event_attributes("cache-metrics")
      |> Map.merge(%{outcome: "miss", size: 0, duration_ms: 5}),
      project
      |> cache_event_attributes("cache-metrics")
      |> Map.merge(%{outcome: "write", size: 1024, duration_ms: 20}),
      content_cache_event_attributes(project, "cache-metrics")
    ])

    summary = ReapiCache.summary(project.id)

    assert summary.transfer_bytes == 7168
    assert_in_delta summary.read_latency_ms, 29 / 3, 0.001
    assert summary.write_latency_ms == 20.0
    assert summary.latency_ms == 12.25
    assert summary.download_throughput_bytes_per_second == 256_000.0
    assert summary.upload_throughput_bytes_per_second == 51_200.0
    assert_in_delta summary.throughput_bytes_per_second, 162_909.09, 0.01

    analytics = ReapiCache.analytics(project.id)
    bucket_index = Enum.find_index(analytics.observation_values, &(&1 > 0))

    assert_in_delta Enum.at(analytics.throughput_values, bucket_index), 162_909.09, 0.01
    assert ReapiCache.observations_present?(project.id)
  end

  test "renders period-scoped cache empty states without onboarding copy", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    ReapiCache.create_cache_events([cache_event_attributes(project, "outside-cache-period")])

    path =
      ~p"/#{organization.account.name}/#{project.name}/bazel-cache?analytics-date-range=custom&analytics-start-date=2000-01-01T00%3A00%3A00Z&analytics-end-date=2001-01-01T00%3A00%3A00Z"

    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(
             live_view,
             "[data-part='analytics-card-chart-section']",
             "No cache observations in the selected period"
           )

    assert has_element?(
             live_view,
             "[data-part='bazel-cache-activity-card']",
             "No cache observations in the selected period"
           )

    refute has_element?(live_view, "#bazel-cache", "Get started")
  end

  test "does not render an empty metrics card for a hidden targets count", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    invocation =
      project
      |> invocation_attributes("targets-only", "build", finished_at)
      |> Map.merge(%{
        cpu_time_ms: 0,
        actions_created: 0,
        actions_executed: 0,
        targets_configured: 10,
        packages_loaded: 0
      })

    Bazel.create_invocations([invocation])

    {:ok, live_view, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/invocations/targets-only")

    refute has_element?(live_view, "#bazel-actions-executed")
  end

  test "preserves observation-time analytics for delayed cache events", %{project: project} do
    observed_at = ~U[2026-09-01 12:00:00.000000Z]

    event =
      project
      |> cache_event_attributes("delayed-cache-event")
      |> Map.merge(%{
        id: UUIDv7.generate(),
        observed_at: observed_at,
        inserted_at: ~N[2026-09-02 12:00:00]
      })

    IngestRepo.insert_all(CacheEvent, [event])

    summary =
      ReapiCache.summary(project.id,
        start_datetime: ~U[2026-09-01 00:00:00Z],
        end_datetime: ~U[2026-09-02 00:00:00Z]
      )

    assert summary.hits == 1
  end

  test "renders an empty invocation state", %{conn: conn, organization: organization, project: project} do
    {:ok, live_view, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/builds")
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "[data-part=empty-bazel-invocations-card-section]")
  end

  test "returns zero duration aggregates for an empty period", %{project: project} do
    summary =
      Bazel.summary(project.id,
        start_datetime: ~U[2000-01-01 00:00:00Z],
        end_datetime: ~U[2001-01-01 00:00:00Z]
      )

    assert summary.average_duration_ms == 0
    assert summary.median_duration_ms == 0
    assert summary.p90_duration_ms == 0
    assert summary.p99_duration_ms == 0
  end

  test "renders invocation logs from a Bazel test run", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: project.account_id,
        build_system: "bazel",
        bazel_invocation_id: "invocation-1"
      )

    Bazel.create_invocation_logs([
      %{
        id: UUIDv7.generate(),
        invocation_id: "invocation-1",
        sequence_number: 10,
        stream: "stdout",
        message: "Bazel test output",
        project_id: project.id,
        observed_at: ~N[2026-09-04 12:00:00]
      }
    ])

    finished_at = ~N[2026-09-04 12:00:01]
    Bazel.create_invocations([invocation_attributes(project, "invocation-1", "test", finished_at)])

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=logs"
      )

    assert has_element?(live_view, "[data-part=bazel-invocation-logs]", "Bazel test output")
    assert has_element?(live_view, "a", "Logs")

    assert has_element?(
             live_view,
             "a[href='/#{organization.account.name}/#{project.name}/builds/invocations/invocation-1']",
             "Bazel invocation"
           )

    refute has_element?(live_view, "[data-part=metadata]", "Mac device")
    refute has_element?(live_view, "[data-part=metadata]", "macOS version")
  end

  defp invocation_attributes(project, invocation_id, command, finished_at) do
    %{
      invocation_id: invocation_id,
      command: command,
      target_patterns: ["//App:App"],
      bazel_version: "8.1.0",
      git_branch: "main",
      git_commit_sha: "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f",
      cpu_time_ms: 15_503,
      actions_created: 481,
      actions_executed: 89,
      targets_configured: 3_964,
      packages_loaded: 160,
      build_timeline_duration_ms: 8_000,
      build_timeline_lanes: ["Critical path", "Main thread"],
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
