defmodule TuistWeb.GradleTaskExecutionLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Gradle
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{project: project} do
    %{project: project |> Ecto.Changeset.change(build_system: :gradle) |> Tuist.Repo.update!()}
  end

  test "build rows open individual executions and link to the exact task overview", context do
    %{project: project, organization: organization, conn: conn} = context

    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        root_project_name: "Composite project",
        is_ci: true,
        git_branch: "main",
        git_commit_sha: "d73a6294ef18476e86391c98e5a52da986cc1b20",
        tasks: [task(":included"), task(":")]
      )

    execution = Enum.find(Gradle.list_tasks(build_id), &(&1.build_path == ":included"))
    base = "/#{organization.account.name}/#{project.name}"
    build_path = "#{base}/builds/build-runs/#{build_id}"
    execution_path = "#{build_path}/tasks/#{execution.id}"

    {:ok, view, _} = live(conn, build_path)
    assert has_element?(view, "#gradle-tasks-table td[data-selectable] > a[href='#{execution_path}']")

    {:ok, detail, html} =
      view
      |> element("#gradle-tasks-table a[data-part=row-link][href='#{execution_path}']")
      |> render_click()
      |> follow_redirect(conn)

    assert html =~ "Execution details"
    assert length(Floki.find(Floki.parse_fragment!(html), "#gradle-task-execution .noora-card")) == 1
    refute has_element?(detail, "details")
    assert length(Floki.find(Floki.parse_fragment!(html), "[data-part=metadata-grid]")) == 1
    assert has_element?(detail, "[data-part=metadata]", "main")
    assert has_element?(detail, "[data-part=metadata]", "d73a6294ef18")
    refute html =~ "d73a6294ef18476e86391c98e5a52da986cc1b20"
    assert has_element?(detail, "h1", ":app:compileJava")
    assert has_element?(detail, "[data-part=title] .noora-badge[data-color=success]", "Succeeded")
    assert has_element?(detail, "[data-part=metadata]", "CI")
    assert has_element?(detail, "[data-part=metadata]", "1.2s")
    assert has_element?(detail, "[data-part=metadata]", ":included")
    refute html =~ "Input changed"
    assert has_element?(detail, "[data-part=metadata]", "Incremental")
    assert has_element?(detail, "[data-part=back-button][href='#{build_path}']")
    refute has_element?(detail, "[data-part=dependencies-link]")

    link =
      detail
      |> element("[data-part=task-overview-link]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> hd()

    uri = URI.parse(link)
    assert URI.decode(uri.path) == "#{base}/builds/tasks/:app:compileJava"

    assert URI.decode_query(uri.query) == %{
             "root_project_name" => "Composite project",
             "build_path" => ":included",
             "task_type" => "org.gradle.api.tasks.compile.JavaCompile"
           }

    {:ok, overview, _} = detail |> element("[data-part=task-overview-link]") |> render_click() |> follow_redirect(conn)
    render_async(overview, 3000)
    assert has_element?(overview, "#gradle-bottleneck-history a[data-part=row-link][href='#{execution_path}']")
    assert length(Floki.find(Floki.parse_fragment!(render(overview)), "#gradle-bottleneck-history tbody tr")) == 1

    {:ok, cache, _} = live(conn, build_path <> "?tab=gradle-cache")
    assert has_element?(cache, "#gradle-cacheable-tasks-table a[data-part=row-link][href='#{execution_path}']")
  end

  test "non-cacheable and legacy executions show cacheability", context do
    %{project: project, organization: organization, conn: conn} = context

    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        tasks: [
          %{
            task_path: ":clean",
            outcome: "failed",
            duration_ms: 0,
            cacheable: false,
            execution: %{
              build_path: ":",
              task_type: "Delete",
              cacheability: "disabled"
            }
          },
          %{task_path: ":legacy", outcome: "skipped", duration_ms: 0, cacheable: false}
        ]
      )

    for execution <- Gradle.list_tasks(build_id) do
      {:ok, detail, html} =
        live(conn, "/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}/tasks/#{execution.id}")

      assert html =~ "0ms"
      refute html =~ "Download duration"
      refute has_element?(detail, "[data-part=dependencies-link]")

      if execution.task_path == ":clean" do
        assert html =~ "Not cacheable"
        refute html =~ "Caching has been disabled for the task"
        assert has_element?(detail, "[data-part=metadata]", "Root build")
        assert has_element?(detail, "[data-part=title] .noora-badge[data-color=destructive]", "Failed")
      else
        assert html =~ "Unknown cacheability"
        assert has_element?(detail, "[data-part=title] .noora-badge[data-color=neutral]", "Skipped")
      end
    end
  end

  test "cache badge combines eligibility and observed cache results", context do
    %{project: project, organization: organization, conn: conn} = context

    scenarios = [
      {"remote_hit", "cacheable", "hit", "Hit", "information"},
      {"local_hit", "cacheable", "not_requested", "Local hit", "information"},
      {"executed", "cacheable", "miss", "Miss", "warning"},
      {"executed", "cacheable", "error", "Error", "destructive"},
      {"executed", "cacheable", "not_requested", "Cacheable", "neutral"},
      {"executed", "disabled", "not_requested", "Not cacheable", "neutral"}
    ]

    tasks =
      scenarios
      |> Enum.with_index()
      |> Enum.map(fn {{outcome, cacheability, lookup, _, _}, index} ->
        base = task(":")

        %{
          base
          | task_path: ":task#{index}",
            outcome: outcome,
            execution: %{base.execution | cacheability: cacheability, remote_cache_lookup_outcome: lookup}
        }
      end)

    build_id = GradleFixtures.build_fixture(project_id: project.id, tasks: tasks)
    executions = Gradle.list_tasks(build_id)

    for {{_, _, _, label, color}, index} <- Enum.with_index(scenarios) do
      execution = Enum.find(executions, &(&1.task_path == ":task#{index}"))

      {:ok, view, html} =
        live(conn, "/#{organization.account.name}/#{project.name}/builds/build-runs/#{build_id}/tasks/#{execution.id}")

      assert has_element?(view, "[data-part=cache-status][data-color=#{color}]", label)
      refute html =~ "Remote lookup"
      refute html =~ "Not requested"
    end
  end

  test "execution lookup rejects another project, another build and invalid IDs", context do
    %{project: project, organization: organization, conn: conn} = context
    other_project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
    build_id = GradleFixtures.build_fixture(project_id: project.id, tasks: [task(":")])
    other_build_id = GradleFixtures.build_fixture(project_id: other_project.id, tasks: [task(":")])
    [execution] = Gradle.list_tasks(build_id)
    [other_execution] = Gradle.list_tasks(other_build_id)

    for {parent_id, task_id} <- [
          {other_build_id, other_execution.id},
          {other_build_id, execution.id},
          {build_id, other_execution.id},
          {build_id, UUIDv7.generate()},
          {build_id, "invalid"},
          {"invalid", execution.id}
        ] do
      assert {:error, :not_found} = Gradle.get_task(project.id, parent_id, task_id)

      assert_raise NotFoundError, fn ->
        live(conn, "/#{organization.account.name}/#{project.name}/builds/build-runs/#{parent_id}/tasks/#{task_id}")
      end
    end
  end

  defp task(build_path) do
    %{
      task_path: ":app:compileJava",
      outcome: "executed",
      duration_ms: 1200,
      cacheable: true,
      started_at: DateTime.utc_now(),
      execution: %{
        build_path: build_path,
        task_type: "org.gradle.api.tasks.compile.JavaCompile",
        cacheability: "cacheable",
        incremental: true,
        remote_cache_lookup_outcome: "miss"
      }
    }
  end
end
