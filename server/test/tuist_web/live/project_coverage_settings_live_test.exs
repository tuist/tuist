defmodule TuistWeb.ProjectCoverageSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Workers.RecomputeTotalsWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  defp settings_path(organization, project), do: ~p"/#{organization.account.name}/#{project.name}/settings/coverage"

  test "is a tab of the project's settings", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    assert has_element?(lv, "#project-settings a[href='#{settings_path(organization, project)}']", "Code coverage")
  end

  test "saves the gates, exclusions, Git history and tracked files", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, settings_path(organization, project))

    assert has_element?(lv, "#coverage-gates-enabled")
    assert has_element?(lv, "[data-part='retention']", "90 days")

    # Nothing is excluded until the project says what is generated.
    assert lv |> element("#coverage-excluded-path-globs") |> render() =~ ~r/<textarea[^>]*>\s*<\/textarea>/

    lv |> element("#coverage-gates-enabled") |> render_click()
    lv |> element("#coverage-patch-partial-runs") |> render_click()
    lv |> element("#coverage-git-history-provider-fallback") |> render_click()
    refute_enqueued(worker: RecomputeTotalsWorker)

    lv
    |> form("#coverage-settings-form", %{
      "min_patch_coverage" => "80",
      "max_total_drop" => "1.5",
      "excluded_path_globs" => "Sources/API/**\n\n  **/*.pb.swift  \n",
      "git_history_window_days" => "120",
      "git_history_window_commits" => "",
      "tracked_file_globs" => "Fixtures/**\n\n  Package.resolved  \n"
    })
    |> render_submit()

    project = Projects.get_project_by_id(project.id)

    assert {project.coverage_gates_enabled, project.coverage_gate_min_patch_coverage,
            project.coverage_gate_max_total_drop} == {true, 80.0, 1.5}

    assert project.coverage_patch_partial_runs == true
    assert project.coverage_excluded_path_globs == ["Sources/API/**", "**/*.pb.swift"]
    assert {project.git_history_window_days, project.git_history_window_commits} == {120, nil}
    assert project.git_history_provider_fallback == true
    assert project.tracked_file_globs == ["Fixtures/**", "Package.resolved"]

    # The past runs' totals follow the new exclusions.
    assert_enqueued(worker: RecomputeTotalsWorker, args: %{project_id: project.id})
  end

  test "does not recompute the totals when the exclusions are unchanged", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, settings_path(organization, project))

    lv |> form("#coverage-settings-form", %{"min_patch_coverage" => "70", "excluded_path_globs" => ""}) |> render_submit()

    assert Projects.get_project_by_id(project.id).coverage_gate_min_patch_coverage == 70.0
    refute_enqueued(worker: RecomputeTotalsWorker)
  end

  test "is not found without code coverage or for other build systems", %{conn: conn, organization: organization} do
    bazel = ProjectsFixtures.project_fixture(account: organization.account, build_system: :bazel)

    assert_raise NotFoundError, fn -> live(conn, settings_path(organization, bazel)) end

    xcode = ProjectsFixtures.project_fixture(account: organization.account, build_system: :xcode)
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    assert_raise NotFoundError, fn -> live(conn, settings_path(organization, xcode)) end

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{xcode.name}/settings")
    refute has_element?(lv, "#project-settings", "Code coverage")
  end
end
