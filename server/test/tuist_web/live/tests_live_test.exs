defmodule TuistWeb.TestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  test "a Once project's runs column is headed Run, not Scheme", %{conn: conn, project: project} do
    # Once has no schemes. The shared `scheme` column carries the command the
    # run was invoked with, so the header has to follow the project's build
    # system rather than Xcode's vocabulary.
    once_project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()

    {:ok, _} =
      Tuist.Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: once_project.id,
        account_id: once_project.account_id,
        duration: 1_000,
        status: "success",
        scheme: "once test //...",
        ran_at: DateTime.utc_now(),
        is_ci: false,
        build_system: "once",
        test_modules: [
          %{
            name: "cargo_aqua",
            status: "success",
            duration: 10,
            test_suites: [%{name: "unit", status: "success", duration: 10}],
            test_cases: [
              %{name: "case_1", test_suite_name: "unit", status: "success", duration: 10}
            ]
          }
        ]
      })

    Tuist.Tests.Test.Buffer.flush()

    {:ok, lv, _html} =
      live(conn, ~p"/#{once_project.account.name}/#{once_project.name}/tests")

    render_async(lv, @render_async_timeout)

    # Asserted as a difference against the same page on an Xcode project:
    # "Scheme" appears nowhere for Once, and does for Xcode. A positive match
    # on "Run" alone would hit the sidebar's "Build Runs".
    refute render(lv) =~ "Scheme"

    xcode_project =
      once_project |> Ecto.Changeset.change(build_system: :xcode) |> Tuist.Repo.update!()

    {:ok, xcode_lv, _} =
      live(conn, ~p"/#{xcode_project.account.name}/#{xcode_project.name}/tests")

    render_async(xcode_lv, @render_async_timeout)

    assert render(xcode_lv) =~ "Scheme"
  end

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

  test "hides the line coverage widget from an account without the xcode_coverage flag", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/tests?analytics-selected-widget=coverage")

    render_async(lv, @render_async_timeout)

    refute has_element?(lv, "#widget-coverage")
    refute has_element?(lv, "#coverage-chart")
  end

  test "leaves partial runs out of the line coverage widget", %{
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
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second),
        is_ci: true,
        test_modules: [],
        xcode_coverage: %{
          partial: true,
          files: [
            %{
              path: "Sources/Add.swift",
              git_blob_id: "abc",
              targets: ["Calculator"],
              covered_lines: 1,
              executable_lines: 4,
              line_numbers: [1, 2, 3, 4],
              execution_counts: [1, 0, 0, 0],
              functions: []
            }
          ]
        }
      })

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    refute has_element?(lv, "#widget-coverage", "25.0%")
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
