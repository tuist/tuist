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

  test "lists at most 100 configuration operations", %{project: project} do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        configuration_operations:
          Enum.map(1..101, fn duration_ms ->
            %{
              phase: "project",
              build_path: ":",
              project_path: ":app",
              duration_ms: duration_ms,
              started_at: @now
            }
          end)
      )

    operations = Gradle.list_configuration_operations(build_id)

    assert length(operations) == 100
    assert Enum.map(operations, & &1.duration_ms) == Enum.to_list(101..2//-1)
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

  test "gradle cache tab excludes up_to_date tasks", %{
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
          %{task_path: ":app:compileJava", outcome: "up_to_date", cacheable: true, duration_ms: 500},
          %{task_path: ":app:assembleDebug", outcome: "local_hit", cacheable: true, duration_ms: 200}
        ]
      )

    {:ok, _lv, html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?tab=gradle-cache"
      )

    assert html =~ ":app:compileKotlin"
    assert html =~ ":app:assembleDebug"
    refute html =~ ":app:compileJava"
  end

  test "shows cache-miss diagnostics and setup telemetry", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        configuration_cache: %{
          status: "invalid",
          invalidation_reasons: ["an environment variable changed"]
        },
        configuration_operations: [
          %{
            phase: "build",
            build_path: ":",
            project_path: "",
            duration_ms: 2_300,
            started_at: ~U[2026-08-31 12:00:00Z]
          },
          %{
            phase: "settings",
            build_path: ":",
            project_path: "",
            duration_ms: 640,
            started_at: ~U[2026-08-31 12:00:00Z]
          },
          %{
            phase: "project",
            build_path: ":",
            project_path: ":app",
            duration_ms: 910,
            started_at: ~U[2026-08-31 12:00:00.640Z]
          }
        ],
        artifact_transforms: [
          %{
            transformer_name: "JetifyTransform",
            transform_action_class: "com.example.JetifyTransform",
            subject_name: "example.jar",
            artifact_name: "example.jar",
            consumer_project_path: ":app",
            duration_ms: 200,
            started_at: ~U[2026-08-31 12:00:01Z]
          },
          %{
            transformer_name: "DexingTransform",
            transform_action_class: "com.example.DexingTransform",
            subject_name: "other.jar",
            artifact_name: "other.jar",
            consumer_project_path: ":app",
            duration_ms: 100,
            started_at: ~U[2026-08-31 12:00:02Z]
          }
        ],
        tasks: [
          %{
            task_path: ":app:compileKotlin",
            outcome: "executed",
            cacheable: true,
            duration_ms: 1_000,
            remote_cache_miss: true,
            remote_cache_stored: true
          }
        ]
      )

    {:ok, _lv, cache_html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?tab=gradle-cache"
      )

    assert cache_html =~ "No remote entry, then stored"
    assert cache_html =~ "Confirmed remote misses"

    {:ok, lv, setup_html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?tab=build-setup"
      )

    assert setup_html =~ "Configuration"
    assert setup_html =~ "Filter"
    assert setup_html =~ "Root build"
    assert setup_html =~ ":app"
    assert setup_html =~ "an environment variable changed"
    assert setup_html =~ "JetifyTransform"
    assert setup_html =~ "DexingTransform"

    lv
    |> element("[phx-change=\"search-configuration-operations\"]")
    |> render_change(%{search: ":app"})

    filtered_html = render(lv)
    assert filtered_html =~ ":app"
    refute filtered_html =~ "Root build"

    lv
    |> element("[phx-change=\"search-artifact-transforms\"]")
    |> render_change(%{search: "Dexing"})

    filtered_html = render(lv)
    assert filtered_html =~ "DexingTransform"
    refute filtered_html =~ "JetifyTransform"

    configuration_phase_filter =
      URI.encode_query(%{
        "tab" => "build-setup",
        "filter_configuration_operation_phase_op" => "==",
        "filter_configuration_operation_phase_val" => "settings"
      })

    {:ok, phase_filtered_lv, _phase_filtered_html} =
      live(
        conn,
        "/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}?#{configuration_phase_filter}"
      )

    assert has_element?(phase_filtered_lv, "#gradle-configuration-operations-table td", "Settings")
    refute has_element?(phase_filtered_lv, "#gradle-configuration-operations-table td", "Project")
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
