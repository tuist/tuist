defmodule TuistWeb.GradleTasksLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures

  setup %{project: project} do
    %{project: project |> Ecto.Changeset.change(build_system: :gradle) |> Tuist.Repo.update!()}
  end

  test "widget and metric selections replace browser history and preserve the task context" do
    params = %{"root_project_name" => "SampleProject", "analytics-environment" => "ci"}
    path = "/tuist/android/builds/tasks/%3Aapp%3ApreBuild"

    for {event, payload, expected} <- [
          {"select_widget", %{"widget" => "executions"}, %{"analytics-selected-widget" => "executions"}},
          {"select_widget", %{"widget" => "hit_rate"}, %{"analytics-selected-widget" => "hit_rate"}},
          {"select_duration_metric", %{"type" => "avg_duration_ms"},
           %{"analytics-duration-metric" => "avg_duration_ms", "analytics-selected-widget" => "task_duration"}}
        ] do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, params: params, uri: URI.parse(path)}}
      {:noreply, socket} = TuistWeb.GradleTasksLive.handle_event(event, payload, socket)

      assert {:live, :patch, %{kind: :replace, to: destination}} = socket.redirected
      assert URI.parse(destination).path == path
      assert URI.decode_query(URI.parse(destination).query) == Map.merge(params, expected)
    end
  end

  test "task rankings support search, stable pagination, sorting and CI filtering", context do
    %{project: project, conn: conn, organization: organization} = context

    GradleFixtures.build_fixture(
      project_id: project.id,
      is_ci: true,
      tasks: Enum.map(1..30, &task(":module#{&1}:compile", &1 * 100))
    )

    GradleFixtures.build_fixture(project_id: project.id, is_ci: false, tasks: [task(":local:compile", 5000)])
    path = "/#{organization.account.name}/#{project.name}/builds/tasks"
    {:ok, view, _} = live(conn, path)
    render_async(view, 3000)
    assert has_element?(view, "#gradle-tasks-table")
    assert has_element?(view, "#gradle-tasks-table tbody tr", ":local:compile")

    view |> element("form[phx-change=search]") |> render_change(%{"q" => "module30"})
    render_async(view, 3000)
    assert has_element?(view, "#gradle-tasks-table tbody tr", ":module30:compile")
    refute has_element?(view, "#gradle-tasks-table tbody tr", ":local:compile")

    render_patch(view, path <> "?analytics-environment=ci&sort=executions&order=asc")
    render_async(view, 3000)

    assert view
           |> element("#gradle-tasks-table tbody")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("tr")
           |> length() == 25

    refute render(view) =~ ":local:compile"
    html = view |> element("#gradle-tasks-table") |> render()
    assert html =~ "module"

    render_patch(view, path <> "?filter_git_branch_op=%3D%3D&filter_git_branch_val=missing-branch")
    assert render_async(view, 3000) =~ "No builds in this period"
  end

  test "table toolbar sorts matching tasks and keeps filtering available for empty results", context do
    %{project: project, conn: conn, organization: organization} = context

    for _ <- 1..3 do
      GradleFixtures.build_fixture(project_id: project.id, git_branch: "main", tasks: [task(":frequent:compile", 100)])
    end

    GradleFixtures.build_fixture(project_id: project.id, git_branch: "main", tasks: [task(":slow:compile", 8000)])
    GradleFixtures.build_fixture(project_id: project.id, git_branch: "feature", tasks: [task(":excluded:compile", 9000)])
    path = "/#{organization.account.name}/#{project.name}/builds/tasks"
    {:ok, view, _} = live(conn, path <> "?filter_git_branch_op=%3D%3D&filter_git_branch_val=main")
    html = render_async(view, 3000)
    refute has_element?(view, "[data-part=table-toolbar] #bottlenecks-filter-dropdown")
    assert has_element?(view, "[data-part=table-toolbar] #bottlenecks-sort-by")
    assert has_element?(view, "#bottlenecks-sort-by-label-portal", "Cumulative time")
    refute html =~ "observed</span>"
    refute html =~ "Latest dependency chain"
    assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", ":slow:compile")

    render_patch(view, sort_href(view, "executions"))
    assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", ":frequent:compile")
    assert has_element?(view, "#bottlenecks-sort-by-label-portal", "Executions")
    assert has_element?(view, "#git_branch.noora-filter", "main")
    refute has_element?(view, "#gradle-tasks-table tbody", ":excluded:compile")

    render_patch(view, sort_href(view, "executions"))
    assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", ":slow:compile")

    view |> element("#filter-git_branch-value-popover form") |> render_submit(%{"value" => "missing"})
    assert render_async(view, 3000) =~ "No builds in this period"
    refute has_element?(view, "[data-part=table-toolbar] #bottlenecks-filter-dropdown")
    assert has_element?(view, "#git_branch.noora-filter", "missing")
  end

  test "task detail shows analytics and matching executions", context do
    %{project: project, conn: conn, organization: organization} = context

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "android",
      tasks: [task(":core:compile", 1000), task(":core:test", 300)]
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      root_project_name: "other",
      tasks: [task(":core:compile", 90_000)]
    )

    {:ok, view, _} =
      live(
        conn,
        "/#{organization.account.name}/#{project.name}/builds/tasks/%3Acore%3Acompile?root_project_name=android&build_path=%3A&task_type=Compile&analytics-selected-widget=tasks"
      )

    html = render_async(view, 3000)
    refute html =~ "Execution profile"
    assert has_element?(view, "h1", ":core:compile")
    refute has_element?(view, "#bottleneck-tasks")
    refute html =~ "Builds observed"
    assert has_element?(view, "[phx-value-widget=executions][data-selected]")
    assert Enum.map(chart(view)["series"], & &1["name"]) == ["Executions"]
    refute has_element?(view, "#module-member-tasks")
    assert has_element?(view, "#gradle-bottleneck-history")
    refute html =~ "1m 30s"
  end

  test "task execution outcomes distinguish success, failure and avoided work", context do
    %{project: project, conn: conn, organization: organization} = context

    outcomes = [
      {"executed", "Succeeded", "success"},
      {"failed", "Failed", "destructive"},
      {"local_hit", "Local hit", "information"},
      {"remote_hit", "Remote hit", "information"},
      {"cache_hit", "Cache hit", "information"},
      {"up_to_date", "Up-to-date", "primary"},
      {"skipped", "Skipped", "neutral"},
      {"no_source", "No source", "neutral"}
    ]

    for {outcome, _, _} <- outcomes do
      GradleFixtures.build_fixture(
        project_id: project.id,
        root_project_name: "android",
        requested_tasks: [":app:assemble"],
        tasks: [%{task(":core:compile", 100) | outcome: outcome}]
      )
    end

    {:ok, view, _} =
      live(conn, "/#{organization.account.name}/#{project.name}/builds/tasks/%3Acore%3Acompile?root_project_name=android")

    render_async(view, 3000)

    for {_, label, color} <- outcomes do
      assert has_element?(view, "#gradle-bottleneck-history .noora-badge[data-color=#{color}]", label)
    end

    refute has_element?(view, "#gradle-bottleneck-history .noora-badge", "Executed")
  end

  test "task executions show the project and CI, account or unknown runner with whole-row navigation", context do
    %{project: project, conn: conn, organization: organization} = context
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    for {is_ci, account_id} <- [{true, account.id}, {false, account.id}, {false, 0}] do
      GradleFixtures.build_fixture(
        project_id: project.id,
        root_project_name: "android",
        account_id: account_id,
        is_ci: is_ci,
        custom_tags: ["nightly"],
        tasks: [task(":core:compile", 100)]
      )
    end

    {:ok, view, _} =
      live(conn, "/#{organization.account.name}/#{project.name}/builds/tasks/%3Acore%3Acompile?root_project_name=android")

    render_async(view, 3000)
    assert has_element?(view, "[phx-value-widget=executions][data-selected]")
    assert has_element?(view, "#gradle-bottleneck-history th:first-child", "Project")
    assert has_element?(view, "#gradle-bottleneck-history th", "Ran by")
    refute has_element?(view, "#gradle-bottleneck-history th", "Requested tasks")
    refute has_element?(view, "#gradle-bottleneck-history th", "Environment")
    assert has_element?(view, "#gradle-bottleneck-history [data-part=row-link]", "android")
    assert has_element?(view, "#gradle-bottleneck-history td:first-child .noora-badge", "nightly")
    assert has_element?(view, "#gradle-bottleneck-history td:nth-child(4) .noora-badge[data-color=information]", "CI")
    assert has_element?(view, "#gradle-bottleneck-history td:nth-child(4) .noora-badge[data-color=primary]", account.name)
    assert has_element?(view, "#gradle-bottleneck-history td:nth-child(4) .noora-badge[data-color=neutral]", "Unknown")

    assert has_element?(
             view,
             "#gradle-bottleneck-history td[data-selectable] > [data-part=row-link-overlay][tabindex='-1']"
           )

    assert has_element?(view, "#gradle-bottleneck-history td[data-selectable] > [data-part=row-link]")

    view |> element("form[phx-change=search_task_executions]") |> render_change(%{"search" => "android"})
    render_async(view, 3000)
    assert length(Floki.find(Floki.parse_fragment!(render(view)), "#gradle-bottleneck-history tbody tr")) == 3
  end

  test "task executions table searches and sorts attempts without changing analytics", context do
    %{project: project, conn: conn, organization: organization} = context

    for {branch, duration, outcome} <- [{"main", 100, "executed"}, {"feature", 300, "remote_hit"}] do
      GradleFixtures.build_fixture(
        project_id: project.id,
        root_project_name: "android",
        git_branch: branch,
        requested_tasks: [":app:assemble"],
        tasks: [%{task(":core:compile", duration) | outcome: outcome}]
      )
    end

    path = "/#{organization.account.name}/#{project.name}/builds/tasks/%3Acore%3Acompile?root_project_name=android"
    {:ok, view, _} = live(conn, path)
    render_async(view, 3000)
    assert has_element?(view, "[data-part=task-executions-card]", "Task executions")
    assert has_element?(view, "#gradle-bottleneck-history", "Remote hit")
    assert has_element?(view, "#gradle-bottleneck-history th", "Outcome")
    assert has_element?(view, "#gradle-bottleneck-history th", "Ran at")
    refute has_element?(view, "#gradle-bottleneck-history th", "Cumulative time")

    view |> element("#gradle-bottleneck-history th a", "Duration") |> render_click()
    render_async(view, 3000)
    assert has_element?(view, "#gradle-bottleneck-history tbody tr:first-child", "300ms")
    assert has_element?(view, "#gradle-bottleneck-history tbody tr:first-child", "feature")

    assert has_element?(view, "#gradle-bottleneck-history th a", "Ran at")
    view |> element("#gradle-bottleneck-history th a", "Duration") |> render_click()
    render_async(view, 3000)
    assert has_element?(view, "#gradle-bottleneck-history tbody tr:first-child", "100ms")
    view |> element("#gradle-bottleneck-history th a", "Ran at") |> render_click()
    render_async(view, 3000)

    view |> element("form[phx-change=search_task_executions]") |> render_change(%{"search" => "main"})
    render_async(view, 3000)
    assert has_element?(view, "#gradle-bottleneck-history tbody", "100ms")
    refute has_element?(view, "#gradle-bottleneck-history tbody", "300ms")
    assert has_element?(view, "#bottleneck-executions [data-part=value]", "1")

    view |> element("form[phx-change=search_task_executions]") |> render_change(%{"search" => "missing"})
    render_async(view, 3000)
    assert has_element?(view, "#gradle-bottleneck-history", "No task executions found")
    assert has_element?(view, "#search-task-executions")
  end

  test "shared filters update the list, widgets and selectable chart and can be removed", context do
    %{project: project, conn: conn, organization: organization} = context

    GradleFixtures.build_fixture(
      project_id: project.id,
      git_branch: "main",
      requested_tasks: [":app:jar"],
      tasks: [task(":app:compile", 1000)]
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      git_branch: "feature",
      requested_tasks: [":app:test"],
      tasks: [task(":other:compile", 3000)]
    )

    path = "/#{organization.account.name}/#{project.name}/builds/tasks"

    {:ok, view, _} =
      live(
        conn,
        path <>
          "?filter_git_branch_op=%3D%3D&filter_git_branch_val=main&requested_task=%3Amissing&filter_requested_tasks_op=%3D%3D&filter_requested_tasks_val=%3Amissing"
      )

    render_async(view, 3000)
    assert has_element?(view, "#git_branch.noora-filter", "main")
    refute has_element?(view, "#requested_tasks.noora-filter")
    refute has_element?(view, "#bottlenecks-filter-dropdown", "Requested tasks")
    refute has_element?(view, "#bottleneck-filters-form")
    assert has_element?(view, "#bottleneck-tasks [data-part=value]", "1")
    assert has_element?(view, "[phx-value-widget=executions][data-selected]")
    view |> element("[phx-value-widget=task_duration]") |> render_click()
    render_async(view, 3000)
    percentiles = chart(view)["series"]
    assert Enum.map(percentiles, & &1["name"]) == ["Avg.", "p99", "p90", "p50"]

    assert Enum.all?(percentiles, fn series ->
             series["data"] |> Enum.map(&List.last/1) |> Enum.reject(&is_nil/1) == [1000]
           end)

    view |> element("[phx-value-widget=executions]") |> render_click()
    render_async(view, 3000)
    assert has_element?(view, "[phx-value-widget=executions][data-selected]")
    assert [%{"name" => "Executions", "data" => points}] = chart(view)["series"]
    assert points |> Enum.map(&List.last/1) |> Enum.sum() == 1
    assert has_element?(view, "#git_branch.noora-filter")

    view |> element("#git_branch button[phx-click=update_filter]") |> render_click()
    render_async(view, 3000)
    assert has_element?(view, "#bottleneck-tasks [data-part=value]", "2")
    refute has_element?(view, "#git_branch.noora-filter")

    render_click(view, "add_filter", %{"value" => "git_branch"})
    assert has_element?(view, "#git_branch.noora-filter")
    view |> element("#filter-git_branch-value-popover form") |> render_submit(%{"value" => "main"})
    assert_push_event(view, "close-popover", %{all: true})
    render_async(view, 3000)
    assert has_element?(view, "#gradle-tasks-table tbody", ":app:compile")
    refute has_element?(view, "#gradle-tasks-table tbody", ":other:compile")
    assert has_element?(view, "#bottleneck-tasks [data-part=value]", "1")

    render_click(view, "update_filter", %{
      "type" => "change_operator",
      "payload_filter_id" => "git_branch",
      "value" => "!=~"
    })

    render_async(view, 3000)
    assert has_element?(view, "#gradle-tasks-table tbody", ":other:compile")
    refute has_element?(view, "#gradle-tasks-table tbody", ":app:compile")
  end

  test "detail links retain filters and chart selection without including sibling task metrics", context do
    %{project: project, conn: conn, organization: organization} = context

    GradleFixtures.build_fixture(
      project_id: project.id,
      git_branch: "main",
      root_project_name: "android",
      tasks: [task(":app:compile", 1000), task(":app:test", 5000)]
    )

    path = "/#{organization.account.name}/#{project.name}/builds/tasks/%3Aapp%3Acompile"

    query =
      URI.encode_query(%{
        "root_project_name" => "android",
        "build_path" => ":",
        "task_type" => "Compile",
        "filter_git_branch_op" => "==",
        "filter_git_branch_val" => "main",
        "analytics-selected-widget" => "misses"
      })

    {:ok, view, _} = live(conn, path <> "?" <> query)
    render_async(view, 3000)
    assert has_element?(view, "#git_branch.noora-filter", "main")
    assert has_element?(view, "#bottleneck-task_duration [data-part=value]", "1.0s")
    assert has_element?(view, "[phx-value-widget=hit_rate][data-selected]")

    back =
      view
      |> element("[data-part=back-button]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("a", "href")
      |> hd()

    assert URI.decode_query(URI.parse(back).query) == %{
             "filter_git_branch_op" => "==",
             "filter_git_branch_val" => "main",
             "analytics-selected-widget" => "misses"
           }
  end

  test "environment dropdown filters detail analytics and history and survives navigation", context do
    %{project: project, conn: conn, organization: organization} = context

    for {is_ci, duration} <- [{true, 1000}, {false, 3000}] do
      GradleFixtures.build_fixture(
        project_id: project.id,
        is_ci: is_ci,
        git_branch: "main",
        tasks: [task(":app:compile", duration)]
      )
    end

    path = "/#{organization.account.name}/#{project.name}/builds/tasks/%3Aapp%3Acompile"

    {:ok, view, _} =
      live(conn, path <> "?analytics-environment=ci&filter_git_branch_op=%3D%3D&filter_git_branch_val=main")

    render_async(view, 3000)
    assert has_element?(view, "#bottlenecks-environment-dropdown-label-portal", "CI")
    assert has_element?(view, "#bottleneck-task_duration [data-part=value]", "1.0s")
    assert has_element?(view, "#git_branch.noora-filter", "main")
    refute has_element?(view, "[data-part=table-toolbar] #bottlenecks-detail-filter-dropdown")
    refute has_element?(view, "[data-part=heading] #bottlenecks-detail-filter-dropdown")
    refute has_element?(view, "#is_ci.noora-filter")
    assert length(Floki.find(Floki.parse_fragment!(render(view)), "#gradle-bottleneck-history tbody tr")) == 1

    href =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("#bottlenecks-environment-dropdown-content-portal a[data-value=local]")
      |> Floki.attribute("href")
      |> hd()

    assert URI.decode_query(URI.parse(href).query)["filter_git_branch_val"] == "main"
    render_patch(view, href)
    render_async(view, 3000)
    assert has_element?(view, "#bottlenecks-environment-dropdown-label-portal", "Local")
    assert has_element?(view, "#bottleneck-task_duration [data-part=value]", "3.0s")
    assert length(Floki.find(Floki.parse_fragment!(render(view)), "#gradle-bottleneck-history tbody tr")) == 1

    back = view |> render() |> Floki.parse_fragment!() |> Floki.attribute("[data-part=back-button]", "href") |> hd()
    assert URI.decode_query(URI.parse(back).query)["analytics-environment"] == "local"
    {:ok, list, _} = live(conn, back)
    html = render_async(list, 3000)
    assert has_element?(list, "#bottlenecks-environment-dropdown-label-portal", "Local")
    assert has_element?(list, "#bottleneck-task_duration [data-part=value]", "3.0s")
    refute html =~ "Gradle version"
    refute html =~ "Java version"
  end

  test "widgets render previous-period trends with historical data", context do
    %{project: project, conn: conn, organization: organization} = context
    end_at = DateTime.truncate(DateTime.utc_now(), :second)
    start_at = DateTime.add(end_at, -7, :day)

    GradleFixtures.build_fixture(
      project_id: project.id,
      inserted_at: DateTime.to_naive(end_at),
      tasks: [task(":app:compile", 1000)]
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      inserted_at: start_at |> DateTime.add(-1, :day) |> DateTime.to_naive(),
      tasks: [task(":app:compile", 500)]
    )

    query =
      URI.encode_query(%{
        "analytics-date-range" => "custom",
        "analytics-start-date" => DateTime.to_iso8601(start_at),
        "analytics-end-date" => DateTime.to_iso8601(end_at)
      })

    {:ok, view, _} = live(conn, "/#{organization.account.name}/#{project.name}/builds/tasks?#{query}")
    render_async(view, 3000)
    assert has_element?(view, "#bottleneck-task_duration", "+100.0%")
    assert has_element?(view, "#bottleneck-task_duration", "since last period")
    assert has_element?(view, "#bottleneck-tasks [data-part=value]", "1")
  end

  test "cache trends show absolute changes from zero and percentages from a positive baseline", context do
    %{project: project, conn: conn, organization: organization} = context
    end_at = DateTime.truncate(DateTime.utc_now(), :second)
    start_at = DateTime.add(end_at, -7, :day)
    hit = %{task(":app:compile", 10) | outcome: "remote_hit", remote_cache_miss: false}

    GradleFixtures.build_fixture(
      project_id: project.id,
      inserted_at: start_at |> DateTime.add(-1, :day) |> DateTime.to_naive(),
      tasks: [hit]
    )

    GradleFixtures.build_fixture(
      project_id: project.id,
      inserted_at: DateTime.to_naive(end_at),
      tasks: [task(":app:compile", 1000), task(":core:compile", 1000), task(":feature:compile", 1000)]
    )

    query =
      URI.encode_query(%{
        "analytics-date-range" => "custom",
        "analytics-start-date" => DateTime.to_iso8601(start_at),
        "analytics-end-date" => DateTime.to_iso8601(end_at)
      })

    {:ok, view, _} = live(conn, "/#{organization.account.name}/#{project.name}/builds/tasks?#{query}")
    render_async(view, 3000)
    assert has_element?(view, "#bottleneck-hit_rate [data-part=trend] .noora-badge", "-100.0 pp")
    assert has_element?(view, "#bottleneck-hit_rate [data-part=trend]", "since last period")
    refute has_element?(view, "#bottleneck-task_duration [data-part=trend] .noora-badge")
  end

  test "duration widget defaults to p90, switches metrics and connects only recorded samples", context do
    %{project: project, conn: conn, organization: organization} = context
    end_at = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    start_at = DateTime.add(end_at, -4, :day)

    for {offset, durations} <- [{0, [100, 300, 500]}, {2, [900]}, {4, [0]}] do
      GradleFixtures.build_fixture(
        project_id: project.id,
        git_branch: "main",
        inserted_at: start_at |> DateTime.add(offset, :day) |> DateTime.to_naive(),
        tasks: Enum.with_index(durations, fn duration, index -> task(":app:compile#{index}", duration) end)
      )
    end

    query =
      URI.encode_query(%{
        "analytics-date-range" => "custom",
        "analytics-start-date" => DateTime.to_iso8601(start_at),
        "analytics-end-date" => DateTime.to_iso8601(end_at),
        "filter_git_branch_op" => "==",
        "filter_git_branch_val" => "main",
        "analytics-cache-metric" => "hits",
        "q" => "compile0"
      })

    path = "/#{organization.account.name}/#{project.name}/builds/tasks"
    {:ok, view, _} = live(conn, path <> "?" <> query <> "&analytics-duration-metric=cumulative_duration_ms")
    render_async(view, 3000)
    assert has_element?(view, "#bottleneck-task_duration", "p90 task duration")
    assert has_element?(view, "#bottleneck-task_duration > [data-part=value]", "740ms")

    view |> element("[phx-value-widget=task_duration]") |> render_click()
    render_async(view, 3000)
    percentiles = chart(view)["series"]
    assert Enum.map(percentiles, & &1["name"]) == ["Avg.", "p99", "p90", "p50"]
    refute has_element?(view, "#bottleneck-task_duration", "Cumulative task time")
    assert has_element?(view, "#gradle-tasks-table th", "Cumulative time")
    assert Enum.map(Enum.at(percentiles, 2)["data"], &List.last/1) == [460, nil, 900, nil, 0]
    assert Enum.map(hd(percentiles)["data"], &List.last/1) == [300, nil, 900, nil, 0]
    assert Enum.all?(chart(view)["series"], &(&1["connectNulls"] == true and &1["symbol"] == "circle"))

    for {metric, title, value} <- [
          {"avg_duration_ms", "Avg. task duration", "360ms"},
          {"p50_duration_ms", "p50 task duration", "300ms"},
          {"p99_duration_ms", "p99 task duration", "884ms"},
          {"p90_duration_ms", "p90 task duration", "740ms"}
        ] do
      render_click(view, "select_duration_metric", %{"type" => metric})
      assert has_element?(view, "#bottleneck-task_duration", title)
      assert has_element?(view, "#bottleneck-task_duration > [data-part=value]", value)
      assert has_element?(view, "#git_branch.noora-filter", "main")
      assert has_element?(view, "#bottleneck-hit_rate")
      assert has_element?(view, "input[name=q][value=compile0]")
      assert length(chart(view)["series"]) == 4
    end

    href =
      view |> render() |> Floki.parse_fragment!() |> Floki.attribute("#gradle-tasks-table tbody a", "href") |> hd()

    assert URI.decode_query(URI.parse(href).query)["analytics-duration-metric"] == "p90_duration_ms"
    {:ok, detail, _} = live(conn, href)
    render_async(detail, 3000)
    back = detail |> render() |> Floki.parse_fragment!() |> Floki.attribute("[data-part=back-button]", "href") |> hd()
    assert URI.decode_query(URI.parse(back).query)["analytics-duration-metric"] == "p90_duration_ms"
  end

  test "cache hit rate uses a percentage chart, preserves filters and accepts old widget links", context do
    %{project: project, conn: conn, organization: organization} = context
    hit = %{task(":app:compile", 10) | outcome: "remote_hit", remote_cache_miss: false}
    GradleFixtures.build_fixture(project_id: project.id, git_branch: "main", tasks: [hit])
    GradleFixtures.build_fixture(project_id: project.id, git_branch: "main", tasks: [hit])
    GradleFixtures.build_fixture(project_id: project.id, git_branch: "main", tasks: [task(":app:compile", 1000)])
    GradleFixtures.build_fixture(project_id: project.id, git_branch: "other", tasks: [hit])
    path = "/#{organization.account.name}/#{project.name}/builds/tasks"

    {:ok, view, _} =
      live(conn, path <> "?analytics-selected-widget=hits&filter_git_branch_op=%3D%3D&filter_git_branch_val=main")

    render_async(view, 3000)
    assert has_element?(view, "#bottleneck-hit_rate [data-part=value]", "66.7%")
    assert has_element?(view, "[phx-value-widget=hit_rate][data-selected]")
    refute has_element?(view, "#bottleneck-hit_rate button")
    assert [%{"name" => "Cache hit rate", "type" => "line", "data" => points}] = chart(view)["series"]
    assert Enum.reject(Enum.map(points, &List.last/1), &is_nil/1) == [66.7]
    assert chart(view)["yAxis"]["max"] == 100
    assert chart(view)["yAxis"]["axisLabel"]["formatter"] == "{value}%"
    assert has_element?(view, "#git_branch.noora-filter", "main")
    render_patch(view, sort_href(view, "p99_duration_ms"))
    assert has_element?(view, "[phx-value-widget=hit_rate][data-selected]")
    render_click(view, "select_widget", %{"widget" => "executions"})
    render_click(view, "select_widget", %{"widget" => "hit_rate"})
    assert has_element?(view, "#bottleneck-hit_rate [data-part=value]", "66.7%")
  end

  test "non-cacheable and unknown tasks do not show a misleading zero cache hit rate", context do
    %{project: project, conn: conn, organization: organization} = context

    for {state, label} <- [{"disabled", "Not cacheable"}, {"unknown", "Unknown cacheability"}, {"cacheable", "0%"}] do
      execution =
        ":#{state}"
        |> task(100)
        |> Map.put(:remote_cache_miss, false)
        |> put_in([:execution, :cacheability], state)

      GradleFixtures.build_fixture(
        project_id: project.id,
        root_project_name: "android",
        tasks: [execution]
      )

      {:ok, view, _} =
        live(
          conn,
          "/#{organization.account.name}/#{project.name}/builds/tasks/%3A#{state}?root_project_name=android&analytics-selected-widget=misses"
        )

      render_async(view, 3000)
      assert has_element?(view, "#bottleneck-hit_rate", label)

      if state == "cacheable" do
        assert has_element?(view, "#bottleneck-analytics-chart")
      else
        refute has_element?(view, "#bottleneck-analytics-chart")
        refute has_element?(view, "#bottleneck-hit_rate [data-part=trend]")
        assert has_element?(view, "#cache-hit-rate-unavailable", label)
      end
    end
  end

  test "task table uses shared cells, explicit cache badges and sortable duration percentiles", context do
    %{project: project, conn: conn, organization: organization} = context

    disabled =
      ":disabled"
      |> task(100)
      |> Map.put(:cacheable, true)
      |> Map.put(:remote_cache_miss, false)
      |> put_in([:execution, :cacheability], "disabled")

    unknown = disabled |> put_in([:execution, :cacheability], "unknown") |> Map.put(:task_path, ":unknown")
    local = %{task(":local", 1) | outcome: "local_hit", remote_cache_miss: false}
    GradleFixtures.build_fixture(project_id: project.id, tasks: [disabled, unknown, local])

    for duration <- [100, 300] do
      GradleFixtures.build_fixture(project_id: project.id, tasks: [task(":slow", duration)])
    end

    path = "/#{organization.account.name}/#{project.name}/builds/tasks"
    {:ok, view, _} = live(conn, path)
    render_async(view, 3000)
    assert has_element?(view, "#gradle-tasks-table td:first-child [data-type=text_and_description]", ":slow")
    assert has_element?(view, "#gradle-tasks-table .noora-badge", "Not cacheable")
    assert has_element?(view, "#gradle-tasks-table .noora-badge", "Unknown cacheability")
    assert has_element?(view, "#gradle-tasks-table td:nth-child(4) [data-type=text]", "0%")
    refute has_element?(view, "#gradle-tasks-table .noora-badge", "Cacheable")
    refute has_element?(view, "#gradle-tasks-table th", "Dependent modules")
    refute has_element?(view, "#gradle-tasks-table th", "Longest chain")

    for percentile <- ~w(p50 p90 p99) do
      assert has_element?(view, "#gradle-tasks-table th", percentile)
      render_patch(view, sort_href(view, "#{percentile}_duration_ms"))
      assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", ":slow")
      assert has_element?(view, "#gradle-tasks-table tbody tr:last-child", ":local")
    end

    assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", "200ms")
    assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", "280ms")
    assert has_element?(view, "#gradle-tasks-table tbody tr:first-child", "298ms")
  end

  defp sort_href(view, field) do
    view
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("#bottlenecks-sort-by-content-portal a[data-value='#{field}']", "href")
    |> hd()
  end

  defp chart(view) do
    view
    |> element("#bottleneck-analytics-chart [data-part=data]")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> JSON.decode!()
  end

  test "malformed scalar filters are ignored in task list and detail", context do
    %{project: project, conn: conn, organization: organization} = context
    GradleFixtures.build_fixture(project_id: project.id, tasks: [task(":app:compile", 100)])
    path = "/#{organization.account.name}/#{project.name}/builds/tasks"
    malformed = "?root_project_name[]=other&task_type[]=Other&build_path[]=other&q[]=other&execution-search[]=other"

    for suffix <- ["", "/%3Aapp%3Acompile"] do
      {:ok, view, _} = live(conn, path <> suffix <> malformed)
      render_async(view, 3000)
      assert has_element?(view, "#bottleneck-executions [data-part=value]", "1")
    end
  end

  defp task(path, duration) do
    %{
      task_path: path,
      outcome: "executed",
      duration_ms: duration,
      cacheable: true,
      remote_cache_miss: true,
      execution: %{
        build_path: ":",
        task_type: "Compile",
        cacheability: "cacheable",
        remote_cache_lookup_outcome: "miss"
      }
    }
  end
end
