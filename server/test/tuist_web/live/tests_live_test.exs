defmodule TuistWeb.TestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Test.Buffer
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  for build_system <- [:mix, :xcode, :gradle, :bazel] do
    test "shows #{build_system} test cases before they have enough duration samples", %{
      conn: conn,
      project: project
    } do
      project =
        project
        |> Ecto.Changeset.change(build_system: unquote(build_system))
        |> Tuist.Repo.update!()

      {:ok, _} =
        Tuist.Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 100,
          status: "success",
          scheme: "",
          ran_at: DateTime.utc_now(),
          is_ci: false,
          build_system: Atom.to_string(unquote(build_system)),
          test_modules: [
            %{
              name: "FreshTests",
              status: "success",
              duration: 100,
              test_cases: [
                %{name: "first_sample", test_suite_name: "", status: "success", duration: 100}
              ]
            }
          ]
        })

      Buffer.flush()

      {:ok, lv, _} = live(conn, ~p"/#{project.account.name}/#{project.name}/tests")
      render_async(lv, 5_000)

      assert has_element?(lv, "[data-part='test-cases'] .test-case-card", "first_sample")
      refute has_element?(lv, "[data-part='test-cases']", "No test cases yet")
      refute has_element?(lv, "[data-part='test-cases']", "Slowest test cases")
      refute has_element?(lv, ".test-case-card [data-part='duration']")
    end
  end

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

    Buffer.flush()

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
