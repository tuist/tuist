defmodule TuistWeb.GradleBuildLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Gradle
  alias TuistTestSupport.Fixtures.GradleFixtures

  @now NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

  setup %{project: project, conn: conn} do
    project =
      project
      |> Ecto.Changeset.change(build_system: :gradle)
      |> Tuist.Repo.update!()

    conn = Plug.Conn.assign(conn, :selected_project, project)
    %{project: project, conn: conn}
  end

  test "list_tasks with like filter works at the data layer", %{project: project} do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 1000},
          %{task_path: ":app:compileJava", outcome: "executed", cacheable: true, duration_ms: 2000},
          %{task_path: ":lib:test", outcome: "executed", cacheable: false, duration_ms: 500}
        ]
      )

    # No filter — all 3 tasks
    {tasks, _meta} =
      Gradle.list_tasks(build_id, %{
        filters: [],
        page: 1,
        page_size: 25,
        order_by: [:started_at],
        order_directions: [:asc]
      })

    assert length(tasks) == 3

    # Filter with :like — should match 2
    {tasks, _meta} =
      Gradle.list_tasks(build_id, %{
        filters: [%{field: :task_path, op: :like, value: "compile"}],
        page: 1,
        page_size: 25,
        order_by: [:started_at],
        order_directions: [:asc]
      })

    assert length(tasks) == 2
    assert Enum.all?(tasks, fn t -> String.contains?(t.task_path, "compile") end)
  end

  test "shows build details", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        status: "success",
        root_project_name: "my-android-app",
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true, duration_ms: 1000},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true, duration_ms: 2000}
        ]
      )

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}")

    assert has_element?(lv, "h1", "my-android-app")
    assert has_element?(lv, "td", ":app:compileKotlin")
    assert has_element?(lv, "td", ":app:assembleDebug")
  end

  test "search filters tasks by task path via URL params", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 1000},
          %{task_path: ":app:compileJava", outcome: "executed", cacheable: true, duration_ms: 2000},
          %{task_path: ":lib:test", outcome: "executed", cacheable: false, duration_ms: 500}
        ]
      )

    # Visit with search filter in URL
    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?tasks-filter=compileKotlin"
      )

    assert html =~ ":app:compileKotlin"
    refute html =~ ":app:compileJava"
    refute html =~ ":lib:test"
  end

  test "search partial match filters tasks via URL params", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 1000},
          %{task_path: ":app:compileJava", outcome: "executed", cacheable: true, duration_ms: 2000},
          %{task_path: ":lib:test", outcome: "executed", cacheable: false, duration_ms: 500}
        ]
      )

    # Visit with partial search filter — should match both compile tasks
    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?tasks-filter=compile"
      )

    assert html =~ ":app:compileKotlin"
    assert html =~ ":app:compileJava"
    refute html =~ ":lib:test"
  end

  test "search with colons in filter works", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 1000},
          %{task_path: ":lib:test", outcome: "executed", cacheable: false, duration_ms: 500}
        ]
      )

    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?tasks-filter=:app:"
      )

    assert html =~ ":app:compileKotlin"
    refute html =~ ":lib:test"
  end

  test "search event triggers filtering via form change", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 1000},
          %{task_path: ":app:compileJava", outcome: "executed", cacheable: true, duration_ms: 2000},
          %{task_path: ":lib:test", outcome: "executed", cacheable: false, duration_ms: 500}
        ]
      )

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}")

    # All three tasks should be visible initially
    assert has_element?(lv, "td", ":app:compileKotlin")
    assert has_element?(lv, "td", ":app:compileJava")
    assert has_element?(lv, "td", ":lib:test")

    # Trigger the search event via form change
    lv
    |> element("[phx-change=\"search-tasks\"]")
    |> render_change(%{search: "compileKotlin"})

    html = render(lv)

    assert html =~ ":app:compileKotlin"
    refute html =~ ":app:compileJava"
    refute html =~ ":lib:test"
  end
end
