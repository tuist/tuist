defmodule TuistWeb.TestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  test "renders a searchable scheme dropdown", %{
    conn: conn,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "#tests-analytics-scheme-dropdown [data-part='search-input']")
  end

  test "renders the line coverage widget from the runs that gathered coverage", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, _} =
      Tuist.Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: organization.account.id,
        duration: 1000,
        status: "success",
        git_branch: "main",
        git_commit_sha: "abc123",
        # The period ends at the mount's second, so a run stamped in the same second
        # with microseconds would fall just outside it.
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second),
        is_ci: true,
        test_modules: [],
        xcode_coverage: %{
          partial: false,
          unobserved_files: [],
          files: [
            %{
              path: "Sources/Add.swift",
              git_blob_id: "abc",
              targets: ["Calculator"],
              covered_lines: 3,
              executable_lines: 4,
              line_numbers: [1, 2, 3, 4],
              execution_counts: [1, 1, 1, 0],
              functions: []
            }
          ]
        }
      })

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "#widget-coverage", "75.0%")
  end

  test "renders the shared test dashboard for Bazel projects", %{
    conn: conn,
    organization: organization
  } do
    project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :bazel)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "[data-part='analytics']")
    assert has_element?(lv, "#tests-analytics-scheme-dropdown", "Invocation:")
    refute has_element?(lv, "[data-part='selective-testing']")
  end
end
