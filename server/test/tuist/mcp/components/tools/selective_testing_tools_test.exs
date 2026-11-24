defmodule Tuist.MCP.Components.Tools.SelectiveTestingToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.MCP.Components.Tools.ListSelectiveTestingChangedFiles
  alias Tuist.MCP.Components.Tools.ListSelectiveTestingTests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.TestSelectionFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    impact_run =
      TestSelectionFixtures.run_fixture(
        project_id: project.id,
        requested_modules: ["AppTests"],
        selected: [
          %{name: "test_load()", matched_path: "Sources/Search.swift"},
          %{name: "test_new()", reason: "no_evidence"}
        ]
      )

    TestSelectionFixtures.diff_fixture(
      project_id: project.id,
      changed_files: [%{path: "Sources/Search.swift"}, %{path: "README.md"}]
    )

    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_impact_run_id: impact_run.id)

    %{conn: assign(conn, :current_subject, user), user: user, test_run: test_run}
  end

  defp structured(%{"structuredContent" => content}), do: content

  test "list_selective_testing_tests lists the run's decided tests with why", %{conn: conn, test_run: test_run} do
    assert %{
             "tests" => [
               %{"name" => "test_load()", "reason" => "impacted", "matched_path" => "Sources/Search.swift"},
               %{"name" => "test_new()", "reason" => "no_evidence", "matched_path" => nil}
             ],
             "pagination_metadata" => %{"total_count" => 2}
           } = conn |> ListSelectiveTestingTests.call(%{"test_run_id" => test_run.id}) |> structured()

    assert %{"tests" => [%{"name" => "test_new()"}]} =
             conn
             |> ListSelectiveTestingTests.call(%{"test_run_id" => test_run.id, "reason" => "no_evidence"})
             |> structured()
  end

  test "list_selective_testing_changed_files lists the run's changed files", %{conn: conn, test_run: test_run} do
    assert %{
             "changed_files" => [
               %{"path" => "Sources/Search.swift", "selected_tests_count" => 1},
               %{"path" => "README.md", "selected_tests_count" => 0}
             ]
           } = conn |> ListSelectiveTestingChangedFiles.call(%{"test_run_id" => test_run.id}) |> structured()
  end

  test "doesn't read another account's run", %{conn: conn} do
    other = ProjectsFixtures.project_fixture()
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: other.id)

    assert %{"isError" => true} = ListSelectiveTestingTests.call(conn, %{"test_run_id" => test_run.id})
  end
end
