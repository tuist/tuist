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

  # The modals render their bodies through portals, so their events are pushed directly.
  defp save(lv, form, fields) do
    render_hook(lv, "update_form", Map.put(fields, "form", form))
    render_hook(lv, "save_form", %{"form" => form})
  end

  test "saves each setting from its toggle or modal", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, settings_path(organization, project))

    assert has_element?(lv, "[data-part='excluded-paths-card-section'] .noora-tag", "Nothing excluded")
    assert has_element?(lv, "[data-part='gates-card-section'] .noora-tag", "No thresholds")
    assert has_element?(lv, "[data-part='retention-card-section'] .noora-tag", "90 days")

    lv |> element("#coverage-gates-enabled") |> render_click()
    lv |> element("#coverage-patch-partial-runs") |> render_click()
    lv |> element("#coverage-git-history-provider-fallback") |> render_click()
    refute_enqueued(worker: RecomputeTotalsWorker)

    save(lv, "gates", %{"min_patch_coverage" => "80", "max_total_drop" => "1.5"})
    save(lv, "git_history", %{"window_days" => "120", "window_commits" => ""})
    save(lv, "tracked_files", %{"globs" => "Fixtures/**\n\n  Package.resolved  \n"})
    refute_enqueued(worker: RecomputeTotalsWorker)
    save(lv, "excluded_paths", %{"globs" => "Sources/API/**\n\n  **/*.pb.swift  \n"})

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

    assert has_element?(lv, "[data-part='gates-card-section'] .noora-tag", "Patch coverage at least 80.0%")
    assert has_element?(lv, "[data-part='excluded-paths-card-section'] .noora-tag", "Sources/API/**")
    assert has_element?(lv, "[data-part='git-history-card-section'] .noora-tag", "120 days")
  end

  test "discards a modal's edits on cancel", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, settings_path(organization, project))

    render_hook(lv, "update_form", %{"form" => "gates", "min_patch_coverage" => "70", "max_total_drop" => ""})
    render_hook(lv, "close_modal", %{"form" => "gates"})
    render_hook(lv, "save_form", %{"form" => "gates"})

    assert Projects.get_project_by_id(project.id).coverage_gate_min_patch_coverage == nil
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
