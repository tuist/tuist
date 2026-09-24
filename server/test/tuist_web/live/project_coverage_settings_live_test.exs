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

  test "saves each setting from its modal", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, settings_path(organization, project))

    assert has_element?(lv, "[data-part='excluded-paths-card-section'] .noora-tag", "Nothing excluded")

    save(lv, "tracked_files", %{"globs" => "Fixtures/**\n\n  Package.resolved  \n"})
    refute_enqueued(worker: RecomputeTotalsWorker)
    save(lv, "excluded_paths", %{"globs" => "Sources/API/**\n\n  **/*.pb.swift  \n"})

    project = Projects.get_project_by_id(project.id)

    assert project.coverage_excluded_path_globs == ["Sources/API/**", "**/*.pb.swift"]
    assert project.tracked_file_globs == ["Fixtures/**", "Package.resolved"]

    # The past runs' totals follow the new exclusions.
    assert_enqueued(worker: RecomputeTotalsWorker, args: %{project_id: project.id})

    assert has_element?(lv, "[data-part='excluded-paths-card-section'] .noora-tag", "Sources/API/**")
    assert has_element?(lv, "[data-part='tracked-files-card-section'] .noora-tag", "Package.resolved")

    # The history window is settled by the server, not per project.
    refute has_element?(lv, "#coverage-git-history-modal")
  end

  test "discards a modal's edits on cancel", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, settings_path(organization, project))

    render_hook(lv, "update_form", %{"form" => "tracked_files", "globs" => "Fixtures/**"})
    render_hook(lv, "close_modal", %{"form" => "tracked_files"})
    render_hook(lv, "save_form", %{"form" => "tracked_files"})

    assert Projects.get_project_by_id(project.id).tracked_file_globs == nil
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
