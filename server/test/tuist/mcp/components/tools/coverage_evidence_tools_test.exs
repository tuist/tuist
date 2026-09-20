defmodule Tuist.MCP.Components.Tools.CoverageEvidenceToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.MCP.Components.Tools.GetTestRunCoverageEvidence
  alias Tuist.MCP.Components.Tools.ListTestCoverageEvidenceFiles
  alias Tuist.MCP.Components.Tools.ListTestRunNotRunTests
  alias Tuist.MCP.Components.Tools.ListTestsCoveringFile
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

    run =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [CoverageFixtures.file("Sources/A.swift", [1, 1, 0, 0]), CoverageFixtures.file("Sources/B.swift", [1, 1])],
        %{
          recompute: false,
          test_modules: [
            %{
              name: "AppTests",
              status: "success",
              duration: 10,
              test_cases: [%{name: "testA()", test_suite_name: "ATests", status: "success", duration: 5}]
            }
          ],
          enumerated_tests: [
            %{module: "AppTests", suite: "ATests", name: "testA()"},
            %{module: "AppTests", suite: "BTests", name: "testB()"}
          ],
          coverage_evidence: %{
            paths: ["Sources/A.swift", "Sources/B.swift"],
            scopes: [
              %{kind: "test", module: "AppTests", suite: "ATests", name: "testA()", files: [0]},
              %{kind: "target", module: "AppTests", suite: "", name: "", files: [0, 1]}
            ]
          }
        }
      )

    %{conn: %Plug.Conn{assigns: %{current_subject: :subject}}, run: run}
  end

  defp call(tool, conn, args) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = result = tool.call(conn, args)
    refute Map.get(result, "isError"), text
    JSON.decode!(text)
  end

  test "a run reports its evidence as it was ingested with it", %{conn: conn, run: run} do
    result = call(GetTestRunCoverageEvidence, conn, %{"test_run_id" => run.id})

    assert %{"tests" => 1, "tests_without_evidence" => 0, "targets" => 1, "files" => 2} = result["summary"]
    assert [%{"kind" => "test", "scope_id" => "AppTests/ATests/testA()", "files_count" => 1}] = result["scopes"]

    assert %{"scopes" => [%{"scope_id" => "AppTests", "files_count" => 2}], "total_count" => 1} =
             call(GetTestRunCoverageEvidence, conn, %{"test_run_id" => run.id, "kind" => "target"})
  end

  test "a test's files carry the blob of the run's own coverage", %{conn: conn, run: run} do
    args = %{"test_run_id" => run.id, "module" => "AppTests", "suite" => "ATests", "name" => "testA()"}

    assert call(ListTestCoverageEvidenceFiles, conn, args)["files"] == [
             %{"path" => "Sources/A.swift", "scope" => "test", "git_blob_id" => "blob-Sources/A.swift"},
             %{"path" => "Sources/B.swift", "scope" => "target", "git_blob_id" => "blob-Sources/B.swift"}
           ]
  end

  test "a file names the tests behind it", %{conn: conn, run: run} do
    assert %{"tests" => [%{"name" => "testA()", "suite_name" => "ATests"}], "targets" => ["AppTests"]} =
             call(ListTestsCoveringFile, conn, %{"test_run_id" => run.id, "path" => "Sources/A.swift"})

    assert %{"tests" => [], "targets" => ["AppTests"]} =
             call(ListTestsCoveringFile, conn, %{"test_run_id" => run.id, "path" => "Sources/B.swift"})
  end

  test "a run names the candidates it left out", %{conn: conn, run: run} do
    assert %{"enumerated_test_count" => 2, "not_run_test_count" => 1, "tests" => [%{"name" => "testB()"}]} =
             call(ListTestRunNotRunTests, conn, %{"test_run_id" => run.id})
  end
end
