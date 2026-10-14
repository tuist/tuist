defmodule TuistWeb.CargoBuildsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Cargo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    %{conn: log_in_user(conn, user), user: user, project: project}
  end

  test "splits the Xcode-style Builds home from Build Runs", %{conn: conn, user: user, project: project} do
    build(project, user, command: "check", duration_ms: 90)
    {:ok, home, _} = live(conn, "/#{user.account.name}/#{project.name}/builds")
    html = render_async(home, 5000)
    assert has_element?(home, "#builds[data-build-system=cargo]")

    for id <- [
          "widget-total-builds",
          "widget-build-success-rate",
          "widget-failed-builds",
          "widget-build-duration",
          "cargo-average-build-time-chart",
          "cargo-configuration-insights-chart",
          "cargo-recent-builds-table"
        ] do
      assert has_element?(home, "##{id}")
    end

    configuration_chart =
      home
      |> element("#cargo-configuration-insights-chart [data-part=data]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> JSON.decode!()

    assert configuration_chart["grid"]["left"] == 0
    assert configuration_chart["grid"]["containLabel"] == true
    assert html =~ "Configuration Insights"
    assert html =~ "Recent Builds"
    assert html =~ "cargo check"
    refute has_element?(home, "#cargo-build-runs")
    refute has_element?(home, "#cargo-builds-command")

    {:ok, runs, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/build-runs")
    html = render_async(runs, 5000)
    assert has_element?(runs, "#build-runs")
    assert has_element?(runs, "#cargo-build-runs")
    assert html =~ "Build Runs"
    assert html =~ "90ms"
    refute has_element?(runs, "#widget-total-builds")
  end

  test "all home metrics and charts use the same project, environment and Rust version cohort without nextest", %{
    conn: conn,
    user: user,
    project: project
  } do
    id = build(project, user, duration_ms: 2000, is_ci: true)
    build(project, user, duration_ms: 4000, is_ci: true, status: "failure")
    excluded = build(project, user, duration_ms: 90_000, is_ci: false)
    other_version = build(project, user, command: "check", rust_version: "rustc 1.96.0", duration_ms: 80_000, is_ci: true)
    nextest = build(project, user, command: "nextest", duration_ms: 100_000, is_ci: true, status: "failure")
    other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    other_id = build(other_project, user, duration_ms: 70_000, is_ci: true)

    {:ok, view, _} =
      live(
        conn,
        "/#{user.account.name}/#{project.name}/builds?analytics-environment=ci&analytics-rust-version=rustc+1.97.1&analytics-command=nextest"
      )

    html = render_async(view, 5000)
    assert view |> element("#widget-total-builds [data-part=value]") |> render() =~ "2"
    assert view |> element("#widget-build-success-rate [data-part=value]") |> render() =~ "50.0%"
    assert view |> element("#widget-failed-builds [data-part=value]") |> render() =~ "1"
    assert view |> element("#widget-build-duration [data-part=value]") |> render() =~ "3.0s"
    assert html =~ id
    refute html =~ excluded
    refute html =~ other_version
    refute html =~ nextest
    refute html =~ other_id
    render_hook(view, "select_widget", %{widget: "failed-builds"})

    assert_patch(
      view,
      "/#{user.account.name}/#{project.name}/builds?analytics-environment=ci&analytics-rust-version=rustc+1.97.1&analytics-selected-widget=failed-builds"
    )

    render_async(view, 5000)
    assert has_element?(view, "#cargo-builds-analytics-chart")
    refute has_element?(view, "#cargo-average-build-time-chart")
    render_hook(view, "select_widget", %{widget: "build-duration"})
    assert_patch(view)
    render_hook(view, "select_build_duration_type", %{type: "p90"})
    assert_patch(view)
    render_async(view, 5000)
    assert view |> element("#widget-build-duration") |> render() =~ "p90 build duration"
    render_hook(view, "select_build_duration_chart_type", %{type: "scatter"})
    assert_patch(view)
    html = render_async(view, 5000)
    assert has_element?(view, "#cargo-build-duration-scatter-chart")
    assert html =~ id
    refute html =~ excluded
    refute html =~ other_id
  end

  test "supports shared Build Runs filters, sorting and cursor pagination without losing selections", %{
    conn: conn,
    user: user,
    project: project
  } do
    for duration <- 1..21, do: build(project, user, duration_ms: duration * 1000, status: "failure", is_ci: true)
    excluded = build(project, user, command: "check", duration_ms: 100_000, status: "success", is_ci: false)
    nextest = build(project, user, command: "nextest", duration_ms: 1000, status: "failure", is_ci: true)
    base = "/#{user.account.name}/#{project.name}/builds/build-runs"

    params = %{
      "filter_status_op" => "==",
      "filter_status_val" => "failure",
      "build-runs-sort-by" => "duration",
      "build-runs-sort-order" => "asc"
    }

    {:ok, view, _} = live(conn, base <> "?" <> URI.encode_query(params))
    html = render_async(view, 5000)
    assert length(Floki.find(Floki.parse_fragment!(html), "#cargo-build-runs tbody tr")) == 20
    refute html =~ excluded
    refute html =~ nextest

    next =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("a[href]")
      |> Enum.map(&List.first(Floki.attribute(&1, "href")))
      |> Enum.find(&String.contains?(&1, "after="))

    assert next
    render_patch(view, base <> next)
    html = render_async(view, 5000)
    assert length(Floki.find(Floki.parse_fragment!(html), "#cargo-build-runs tbody tr")) == 1
    refute html =~ excluded
    assert html =~ "21.0s"
    render_patch(view, base <> "?" <> URI.encode_query(%{"filter_is_ci_op" => "==", "filter_is_ci_val" => "false"}))
    html = render_async(view, 5000)
    assert html =~ excluded
    assert length(Floki.find(Floki.parse_fragment!(html), "#cargo-build-runs tbody tr")) == 1
    render_hook(view, "add_filter", %{value: "status"})
    assert_patch(view)
    render_hook(view, "update_filter", %{type: "change_value", payload_filter_id: "status", value: "failure"})
    assert_patch(view)
    render_async(view, 5000)
    refute has_element?(view, "#cargo-build-runs")
    assert render(view) =~ "No data yet"
  end

  test "shows onboarding rather than fabricated data on both empty pages", %{conn: conn, user: user, project: project} do
    for suffix <- ["/builds", "/builds/build-runs"] do
      {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}#{suffix}")
      html = render_async(view, 5000)
      assert html =~ "No data yet"
      assert html =~ "rust-project"
      refute has_element?(view, "#cargo-average-build-time-chart")
      refute has_element?(view, "#cargo-build-runs")
    end
  end

  test "escapes diagnostics and denies cross-project build reads", %{conn: conn, user: user, project: project} do
    {:ok, id} =
      Cargo.create_build(%{
        id: Ecto.UUID.generate(),
        project_id: project.id,
        account_id: user.account.id,
        status: "failure",
        command: "build",
        duration_ms: 90,
        compilations: [
          %{
            name: "widgets",
            source: "src/lib.rs",
            kind: "lib",
            start_offset_ms: 0,
            duration_ms: 90,
            status: "failure",
            dependencies: [],
            diagnostics: [%{severity: "error", message: "unsafe <script>"}]
          }
        ]
      })

    {:ok, view, _html} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}")
    html = render_async(view, 5000)
    assert html =~ "unsafe &lt;script&gt;"
    other = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, "/#{user.account.name}/#{other.name}/builds/cargo-builds/#{id}")
    end
  end

  test "detail uses shared build styling, metadata, diagnostic tabs and paginated compilations", %{
    conn: conn,
    user: user,
    project: project
  } do
    compilations =
      for index <- 1..21 do
        %{
          name: "crate-#{index}",
          source: "src/crate_#{index}.rs",
          kind: "lib",
          dependencies: [],
          start_offset_ms: index * 100,
          duration_ms: index * 1000,
          status: "success",
          diagnostics: [
            %{severity: "warning", message: "unused <script> #{index}", file: "src/crate_#{index}.rs", line: index}
          ]
        }
      end

    id =
      build(project, user,
        duration_ms: 12_000,
        is_ci: true,
        git_branch: "main",
        git_commit_sha: "0123456789abcdef",
        compilations: compilations
      )

    base = "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}"
    {:ok, view, _} = live(conn, base)
    html = render_async(view, 5000)
    assert has_element?(view, "#build-run[data-build-system=cargo]")
    assert has_element?(view, "[data-part=badge-success]")
    assert has_element?(view, "[data-part=metadata-grid]")
    assert has_element?(view, "a[href='/#{user.account.name}/#{project.name}/builds/build-runs']")
    assert html =~ "12.0s"
    assert html =~ "01234567"
    assert html =~ "rustc 1.97.1"
    assert html =~ "unused &lt;script&gt;"
    assert length(Floki.find(Floki.parse_fragment!(html), "#cargo-compilations tbody tr")) == 20
    render_patch(view, base <> "?compilations-page=2")
    html = render_async(view, 5000)
    assert length(Floki.find(Floki.parse_fragment!(html), "#cargo-compilations tbody tr")) == 1
    render_hook(view, "search-compilations", %{search: "crate-21"})
    assert_patch(view)
    assert render_async(view, 5000) =~ "crate-21"
    render_patch(view, base <> "?tab=warnings")
    html = render_async(view, 5000)
    assert has_element?(view, "[data-part=warnings-card] .issue-card")
    assert html =~ "unused &lt;script&gt;"
    refute has_element?(view, "#cargo-compilations")
    render_patch(view, base <> "?tab=errors")
    assert render_async(view, 5000) =~ "No errors detected"
    render_patch(view, base <> "?tab=timeline")
    render_async(view, 5000)
    assert has_element?(view, "[data-part=build-details]")
    refute has_element?(view, "#build-timeline")
  end

  test "detail uses the shared CI badge instead of duplicating an environment label", %{
    conn: conn,
    user: user,
    project: project
  } do
    id = build(project, user, is_ci: true)
    {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}")
    render_async(view, 5000)

    assert has_element?(view, "[data-part=build-details] [data-type=badge] [data-color=information]", "CI")
    refute has_element?(view, "[data-part=build-details] [data-color=primary]", user.account.name)
    refute has_element?(view, "[data-part=metadata] [data-part=title]", "Environment")
  end

  test "detail identifies the local runner with the shared user badge", %{conn: conn, user: user, project: project} do
    runner = AccountsFixtures.user_fixture(preload: [:account])
    id = build(project, user, is_ci: false, account_id: runner.account.id)
    {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}")
    render_async(view, 5000)

    assert has_element?(view, "[data-part=build-details] [data-type=badge] [data-color=primary]", runner.account.name)
    refute has_element?(view, "[data-part=build-details] [data-color=information]", "CI")
    refute has_element?(view, "[data-part=build-details] [data-color=primary]", user.account.name)
    refute has_element?(view, "[data-part=metadata] [data-part=title]", "Environment")
  end

  test "detail uses the shared unknown badge when the local runner is unavailable", %{
    conn: conn,
    user: user,
    project: project
  } do
    id = build(project, user, is_ci: false, account_id: 0)
    {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}")
    render_async(view, 5000)

    assert has_element?(view, "[data-part=build-details] [data-type=badge] [data-color=neutral]", "Unknown")
    refute has_element?(view, "[data-part=build-details] [data-color=primary]")
    refute has_element?(view, "[data-part=build-details] [data-color=information]", "CI")
  end

  test "diagnostic tabs reuse Xcode's count headers and light/dark illustrated empty states", %{
    conn: conn,
    user: user,
    project: project
  } do
    id = build(project, user, [])
    base = "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}"
    {:ok, view, _} = live(conn, base)

    for {tab, title} <- [{"warnings", "Warnings"}, {"errors", "Errors"}] do
      render_patch(view, base <> "?tab=#{tab}")
      render_async(view, 5000)
      section = "#build-run > [data-part=#{tab}-card] > [data-part=#{tab}-card-section]"
      assert view |> element("#{section} > [data-part=header] > [data-part=title]") |> render() =~ title
      assert view |> element("#{section} > [data-part=header] > [data-part=count]") |> render() =~ "0"
      assert has_element?(view, "#{section} > [data-part=empty-state] > [data-part=empty-state-background] svg")

      for theme <- ["light", "dark"] do
        assert has_element?(
                 view,
                 "#{section} > [data-part=empty-state] > [data-part=image] img[data-theme=#{theme}][src='/images/empty_#{tab}_#{theme}.png'][loading=lazy][decoding=async]"
               )
      end

      assert view |> element("#{section} [data-part=subtitle]") |> render() =~ "Looks like you&#39;re having a great day!"
      refute has_element?(view, "#{section} > [data-part=issues-list]")
    end
  end

  test "diagnostic headers count messages rather than files and keep severities separate", %{
    conn: conn,
    user: user,
    project: project
  } do
    id =
      build(project, user,
        status: "failure",
        compilations: [
          %{
            name: "store",
            source: "src/lib.rs",
            kind: "lib",
            dependencies: [],
            start_offset_ms: 0,
            duration_ms: 100,
            status: "failure",
            diagnostics: [
              %{severity: "warning", message: "unused <script> variable", file: "src/lib.rs", line: 1},
              %{severity: "warning", message: "unused import", file: "src/lib.rs", line: 2},
              %{severity: "error", message: "type mismatch", file: "src/lib.rs", line: 3}
            ]
          }
        ]
      )

    base = "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}"
    {:ok, view, _} = live(conn, base <> "?tab=warnings")
    html = render_async(view, 5000)

    assert view |> element("[data-part=warnings-card-section] > [data-part=header] > [data-part=count]") |> render() =~
             "2"

    assert length(Floki.find(Floki.parse_fragment!(html), "[data-part=warnings-card-section] .issue-card")) == 1
    assert html =~ "unused &lt;script&gt; variable"
    refute html =~ "type mismatch"
    refute has_element?(view, "[data-part=warnings-card-section] > [data-part=empty-state]")
    render_patch(view, base <> "?tab=errors")
    html = render_async(view, 5000)
    assert view |> element("[data-part=errors-card-section] > [data-part=header] > [data-part=count]") |> render() =~ "1"
    assert html =~ "type mismatch"
    refute html =~ "unused import"
    refute has_element?(view, "[data-part=errors-card-section] > [data-part=empty-state]")
  end

  test "cache details show reported aggregates and qualification limits", %{conn: conn, user: user, project: project} do
    id =
      build(project, user,
        cache: %{
          version: 1,
          hits: 19,
          misses: 1,
          downloaded_bytes: 72_862_819,
          estimated_compiler_duration_avoided_ns: 9_000_000_000,
          divergences: 1
        }
      )

    {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache")
    html = render_async(view, 5000)
    assert view |> element("#widget-cargo-cache-hits [data-part=value]") |> render() =~ "19"
    assert view |> element("#widget-cargo-cache-hit-rate [data-part=value]") |> render() =~ "95.0%"
    assert has_element?(view, "[data-part=cache-summary-card] > [data-part=widgets-card-section]")
    assert has_element?(view, "#widget-cargo-cache-hits [data-part=title] [data-part=label]", "Task hits")
    assert has_element?(view, "#widget-cargo-cache-misses [data-part=title] [data-part=label]", "Task misses")
    assert length(Floki.find(Floki.parse_fragment!(html), "[data-part=cache-summary-card] .tuist-widget")) == 5
    refute has_element?(view, "[data-part=cache-summary-card] [data-part=metadata-grid]")
    assert has_element?(view, "[data-part=compilation-cache-card] > [data-part=compilation-cache-card-section]")
    assert has_element?(view, "#cargo-cache-actions-breakdown-chart")
    assert has_element?(view, "#widget-cargo-cache-read-latency")
    assert has_element?(view, "#widget-cargo-cache-write-latency")
    assert has_element?(view, "#cacheable-tasks-table")
    assert has_element?(view, "a", "Cacheable Tasks")
    assert has_element?(view, "a", "CAS Outputs")
    assert html =~ "Detailed cache records were not collected"
    assert html =~ "No data"
    refute has_element?(view, "#cargo-cache-activity-table")
    render_patch(view, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache&cache-tab=cas-outputs")
    assert has_element?(view, "#cas-outputs-table")
    assert has_element?(view, "#widget-cargo-download-throughput")
    refute has_element?(view, "#cacheable-tasks-table")
    assert html =~ "including speculative prefetches"
    assert html =~ "Compiler work is not wall-clock time saved"
    assert html =~ "Aggregate hits do not distinguish local and remote restores"
    assert html =~ "Fresh compiler outputs were retained"
    refute has_element?(view, "#cargo-compilation-timings")
  end

  test "cache inspection splits actual task decisions from CAS operations with filters and bounded pages", %{
    conn: conn,
    user: user,
    project: project
  } do
    object = "sha256:#{String.duplicate("b", 64)}:125000"
    untransferred = "sha256:#{String.duplicate("c", 64)}:0"

    tasks =
      for index <- 0..24 do
        %{
          key: "blake3:#{index |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")}:123",
          name: "crate#{String.pad_leading(to_string(index), 3, "0")} <script>",
          kind: "rust",
          status: if(index == 0, do: "miss", else: "hit"),
          cas_keys: [object, untransferred],
          read_duration_ns: 2_000_000
        }
      end

    details = %{
      version: 1,
      truncated: true,
      tasks: tasks,
      cas_outputs: [
        %{key: object, operation: "download", status: "downloaded", size_bytes: 125_000, duration_ns: 1_000_000_000},
        %{key: object, operation: "download", status: "downloaded", size_bytes: 125_000, duration_ns: 1_000_000_000},
        %{key: object, operation: "upload", status: "uploaded", size_bytes: 125_000, duration_ns: 1_000_000_000},
        %{key: object, operation: "upload", status: "present", size_bytes: 125_000, duration_ns: 1_000_000},
        %{key: object, operation: "upload", status: "failed", size_bytes: 125_000, duration_ns: 1_000_000}
      ]
    }

    id = build(project, user, cache: %{version: 1, hits: 24, misses: 1, details: details})
    base = "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache"
    {:ok, view, _} = live(conn, base)
    html = render_async(view, 5000)

    assert length(
             Floki.find(Floki.parse_fragment!(html), "#cacheable-tasks-table tbody > tr:not([data-part=expanded-row])")
           ) == 20

    assert html =~ "crate000 &lt;script&gt;"
    refute html =~ "crate000 <script>"
    assert html =~ "Cache inspection is incomplete"
    assert has_element?(view, "#widget-cargo-cache-read-latency [data-part=value]", "2ms")
    assert html =~ "CAS operations"
    assert has_element?(view, "[data-clipboard-value='#{object}']")
    expanded = html |> Floki.parse_fragment!() |> Floki.find("#cacheable-tasks-table [data-part=expanded-row]") |> hd()
    assert length(Floki.find(expanded, "[data-part=cas-output-item]")) == 2
    assert Floki.find(expanded, "[data-part=cas-output-item] > button") == []
    assert expanded |> Floki.find("[data-part=cas-output-label]") |> Floki.text() =~ "CAS object:"
    refute Floki.text(expanded) =~ "Already present"
    assert has_element?(view, "[data-part=hash-tooltip-content] [data-clipboard-value='#{untransferred}']")
    render_patch(view, base <> "&cache-tasks-page=2")
    assert has_element?(view, "#cacheable-tasks-table", "crate024")
    refute has_element?(view, "#cacheable-tasks-table", "crate000")
    render_patch(view, base <> "&cache-tasks-status=miss")
    assert has_element?(view, "#cacheable-tasks-table", "crate000")
    refute has_element?(view, "#cacheable-tasks-table", "crate001")
    view |> element("#cargo-cache-search-form") |> render_change(%{"search" => "absent"})
    assert has_element?(view, "[data-part=compilation-cache-card]", "No cacheable tasks found")
    render_patch(view, base <> "&cache-tab=cas-outputs")
    assert has_element?(view, "#cas-outputs-table", "Download")
    assert has_element?(view, "#cas-outputs-table", "Upload")
    assert has_element?(view, "#cas-outputs-table", "Already present")
    assert has_element?(view, "#cas-outputs-table", "Failed")
    assert view |> element("[data-part=cacheable-tasks-card-section] [data-part=value]") |> render() =~ ">3<"
    chart = view |> element("#cargo-cas-outputs-breakdown-chart") |> render()
    assert chart =~ "Download"
    assert chart =~ "Upload"
    refute chart =~ "Already present"
    refute chart =~ "Failed"
    assert has_element?(view, "#widget-cargo-download-throughput [data-part=value]", "1.0 Mbps")
    assert has_element?(view, "#widget-cargo-upload-throughput [data-part=value]", "1.0 Mbps")
    refute has_element?(view, "#cacheable-tasks-table")
    render_patch(view, base <> "&cache-read-type=p99")
    assert has_element?(view, "#widget-cargo-cache-read-latency", "p99 latency reading cache keys")
  end

  test "CAS presence checks and failures remain inspectable without a transfer chart", %{
    conn: conn,
    user: user,
    project: project
  } do
    object = "sha256:#{String.duplicate("b", 64)}:125000"

    details = %{
      version: 1,
      truncated: false,
      tasks: [],
      cas_outputs: [
        %{key: object, operation: "upload", status: "present", size_bytes: 125_000, duration_ns: 1_000_000},
        %{key: object, operation: "download", status: "failed", size_bytes: 125_000, duration_ns: 1_000_000}
      ]
    }

    id = build(project, user, cache: %{version: 1, details: details})
    base = "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache&cache-tab=cas-outputs"
    {:ok, view, _} = live(conn, base)
    render_async(view, 5000)

    refute has_element?(view, "#cargo-cas-outputs-breakdown-chart")
    assert has_element?(view, "#cas-outputs-table", "Already present")
    assert has_element?(view, "#cas-outputs-table", "Failed")

    render_patch(view, base <> "&cache-cas-status=present")
    assert has_element?(view, "#cas-outputs-table", "Already present")
    refute has_element?(view, "#cas-outputs-table", "Failed")

    render_patch(view, base <> "&cache-cas-status=failed")
    assert has_element?(view, "#cas-outputs-table", "Failed")
    refute has_element?(view, "#cas-outputs-table", "Already present")
    refute has_element?(view, "#cargo-cas-outputs-breakdown-chart")
  end

  test "cache states and summaries consistently show reuse outcomes rather than lookup internals", %{
    conn: conn,
    user: user,
    project: project
  } do
    tasks =
      for {status, index} <- Enum.with_index(~w(hit miss unconsulted verification)) do
        %{
          key: "blake3:#{String.duplicate(to_string(index), 64)}:123",
          name: "crate-#{status}",
          kind: "rust",
          status: status
        }
      end

    id =
      build(project, user,
        cache: %{
          version: 1,
          hits: 1,
          misses: 1,
          unconsulted: 1,
          verifications: 1,
          details: %{version: 1, truncated: false, tasks: tasks, cas_outputs: []}
        }
      )

    base = "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache"
    {:ok, view, _} = live(conn, base)
    html = render_async(view, 5000)

    assert has_element?(view, "#cacheable-tasks-table th", "Cache")
    assert view |> element("#widget-cargo-cache-hits [data-part=value]") |> render() =~ ">1<"
    assert view |> element("#widget-cargo-cache-misses [data-part=value]") |> render() =~ ">3<"
    assert has_element?(view, "#widget-cargo-cache-hit-rate [data-part=value]", "25.0%")
    assert has_element?(view, "#cargo-tasks-2-status-tooltip", "learn the task inputs")
    assert has_element?(view, "#cargo-tasks-3-status-tooltip", "verify cache correctness")
    refute html =~ "Cache not checked"
    refute html =~ "Verification rebuild"
    refute html =~ "Not queried"
    refute html =~ "Recompiled for verification"

    for status <- ~w(miss unconsulted verification) do
      render_patch(view, base <> "&cache-tasks-status=#{status}")
      assert has_element?(view, "#cargo-cache-status-filter-label-portal", "Missed")
      assert has_element?(view, "#cacheable-tasks-table", "crate-miss")
      assert has_element?(view, "#cacheable-tasks-table", "crate-unconsulted")
      assert has_element?(view, "#cacheable-tasks-table", "crate-verification")
      refute has_element?(view, "#cacheable-tasks-table", "crate-hit")
    end

    render_patch(view, base <> "&cache-tasks-status=hit")
    assert has_element?(view, "#cacheable-tasks-table", "crate-hit")
    refute has_element?(view, "#cacheable-tasks-table", "crate-unconsulted")
  end

  test "a cold build shows compiled tasks as missed with zero cache reuse", %{conn: conn, user: user, project: project} do
    tasks =
      for index <- 0..19 do
        hash = index |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

        %{
          key: "blake3:#{hash}:123",
          name: "crate-#{index}",
          kind: "rust",
          status: "unconsulted"
        }
      end

    id =
      build(project, user,
        cache: %{
          version: 1,
          unconsulted: 20,
          details: %{version: 1, truncated: false, tasks: tasks, cas_outputs: []}
        }
      )

    {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache")
    html = render_async(view, 5000)
    assert view |> element("#widget-cargo-cache-misses [data-part=value]") |> render() =~ ">20<"
    assert has_element?(view, "#widget-cargo-cache-hit-rate [data-part=value]", "0.0%")
    assert has_element?(view, "#cacheable-tasks-table", "Missed")
    assert has_element?(view, "#cargo-cache-actions-breakdown-chart")
    refute html =~ "Cache not checked"
  end

  test "a build without measurements does not invent a cache tab", %{conn: conn, user: user, project: project} do
    id = build(project, user, [])
    {:ok, view, _} = live(conn, "/#{user.account.name}/#{project.name}/builds/cargo-builds/#{id}?tab=cache")
    render_async(view, 5000)
    refute has_element?(view, "#widget-cargo-cache-hits")
    assert has_element?(view, "#cargo-compilation-timings")
  end

  defp build(project, user, opts) do
    {:ok, id} =
      Cargo.create_build(
        Map.merge(
          %{
            id: Ecto.UUID.generate(),
            project_id: project.id,
            account_id: user.account.id,
            status: "success",
            command: "build",
            rust_version: "rustc 1.97.1",
            duration_ms: 2000
          },
          Map.new(opts)
        )
      )

    id
  end
end
