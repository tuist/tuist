defmodule TuistWeb.API.SelectiveTestingControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{conn: Authentication.put_current_user(conn, user), user: user, project: project}
  end

  # A run whose coverage-based selection kept `test_load()`, which
  # `Search.swift` selected and the run passed, and skipped
  # `test_refresh()`. `Package.resolved`, a tracked file, changed too.
  defp selected_run(project) do
    [load, refresh] = for _ <- 1..2, do: UUIDv7.generate()

    TestSelectionFixtures.baseline_fixture(
      project_id: project.id,
      tests: [
        %{test_case_id: load, module_name: "SearchTests", suite_name: "SearchTests", name: "test_load()"},
        %{test_case_id: refresh, module_name: "AuthTests", suite_name: "SessionTests", name: "test_refresh()"}
      ]
    )

    impact_run =
      TestSelectionFixtures.run_fixture(
        project_id: project.id,
        requested_modules: ["SearchTests", "AuthTests"],
        rule_trace: [%{rule: "unaffected", selected: 0, skipped: 1, verdict: "done"}],
        selected: [
          %{
            test_case_id: load,
            module_name: "SearchTests",
            suite_name: "SearchTests",
            name: "test_load()",
            matched_path: "Sources/Search/Search.swift"
          }
        ],
        skipped: [%{test_case_id: refresh, module_name: "AuthTests", suite_name: "SessionTests", name: "test_refresh()"}]
      )

    TestSelectionFixtures.diff_fixture(
      project_id: project.id,
      changed_files: [%{path: "Package.resolved"}, %{path: "Sources/Search/Search.swift"}]
    )

    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: impact_run.id)

    RunsFixtures.test_case_run_fixture(
      project_id: project.id,
      test_run_id: test_run.id,
      test_case_id: load,
      module_name: "SearchTests",
      suite_name: "SearchTests",
      name: "test_load()",
      status: 0
    )

    test_run
  end

  defp path(user, project, test_run_id, read),
    do: "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}/selective-testing/#{read}"

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_run_id/selective-testing/tests" do
    test "lists the tests the selection decided, with why and their outcome here", %{
      conn: conn,
      user: user,
      project: project
    } do
      test_run = selected_run(project)

      response = conn |> get(path(user, project, test_run.id, "tests")) |> json_response(:ok)

      assert [
               %{
                 "name" => "test_load()",
                 "decision" => "selected",
                 "reason" => "impacted",
                 "matched_path" => "Sources/Search/Search.swift",
                 "outcome" => "success"
               },
               %{
                 "name" => "test_refresh()",
                 "decision" => "skipped",
                 "reason" => "unaffected",
                 "matched_path" => nil,
                 "outcome" => nil,
                 "test_case_run_id" => nil
               }
             ] = response["tests"]

      assert response["pagination_metadata"]["total_count"] == 2
    end

    test "filters by decision and pages", %{conn: conn, user: user, project: project} do
      test_run = selected_run(project)

      skipped = conn |> get(path(user, project, test_run.id, "tests") <> "?decision=skipped") |> json_response(:ok)
      assert Enum.map(skipped["tests"], & &1["name"]) == ["test_refresh()"]

      page = conn |> get(path(user, project, test_run.id, "tests") <> "?page=2&page_size=1") |> json_response(:ok)
      assert Enum.map(page["tests"], & &1["name"]) == ["test_refresh()"]

      assert %{"current_page" => 2, "total_pages" => 2, "has_next_page" => false, "has_previous_page" => true} =
               page["pagination_metadata"]
    end

    test "is empty for a run without coverage-based selection", %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      response = conn |> get(path(user, project, test_run.id, "tests")) |> json_response(:ok)

      assert response["tests"] == []
      assert response["pagination_metadata"]["total_count"] == 0
    end

    test "doesn't find another project's run", %{conn: conn, user: user, project: project} do
      other = selected_run(ProjectsFixtures.project_fixture())

      conn = get(conn, path(user, project, other.id, "tests"))

      assert json_response(conn, :not_found)["message"] == "Test run not found."
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/:test_run_id/selective-testing/changed-files" do
    test "lists the changed files, those that selected tests first", %{conn: conn, user: user, project: project} do
      test_run = selected_run(project)

      response = conn |> get(path(user, project, test_run.id, "changed-files")) |> json_response(:ok)

      assert [
               %{"path" => "Sources/Search/Search.swift", "selected_tests_count" => 1, "tracked" => false},
               %{"path" => "Package.resolved", "selected_tests_count" => 0, "tracked" => true}
             ] = response["changed_files"]

      searched = conn |> get(path(user, project, test_run.id, "changed-files") <> "?search=package") |> json_response(:ok)
      assert Enum.map(searched["changed_files"], & &1["path"]) == ["Package.resolved"]
    end

    test "is empty for a run without coverage-based selection", %{conn: conn, user: user, project: project} do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      response = conn |> get(path(user, project, test_run.id, "changed-files")) |> json_response(:ok)

      assert response["changed_files"] == []
    end
  end
end
