defmodule Tuist.Tests.Coverage.EvidenceTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Evidence
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @evidence %{
    paths: ["Sources/Math.swift", "Sources/Text.swift", "Sources/Bootstrap.swift", "Tests/MathTests.swift"],
    scopes: [
      %{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0, 3]},
      %{kind: "test", module: "AppTests", suite: "MathTests", name: "resolves(a/b:)", files: [0, 1, 3]},
      %{"kind" => "suite", "module" => "AppTests", "suite" => "MathTests", "name" => "", "files" => [2]},
      %{kind: "target", module: "AppTests", suite: "", name: "", files: [0, 1, 2, 3]},
      %{kind: "test", module: "AppTests", suite: "MathTests", name: "outOfRange()", files: [9]},
      %{kind: "function", module: "AppTests", suite: "", name: "", files: [0]}
    ]
  }

  setup do
    project = ProjectsFixtures.project_fixture()

    {:ok, test} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10,
            test_cases: [
              %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5},
              %{name: "unattributed()", test_suite_name: "SwiftTests", status: "success", duration: 5},
              %{name: "skipped()", test_suite_name: "SwiftTests", status: "skipped", duration: 0}
            ]
          }
        ]
      )

    %{project: project, test_run: test}
  end

  test "summarizes how much of the run has evidence", %{test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert Evidence.summary(test_run) == %{
             tests: 2,
             suites: 1,
             targets: 1,
             files: 4,
             median_files_per_test: 3,
             max_files_per_test: 3,
             tests_without_evidence: 1
           }
  end

  test "lists the scopes of a kind, those covering most first", %{test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert {[
              %{scope_id: "AppTests/MathTests/resolves(a/b:)", files_count: 3},
              %{scope_id: "AppTests/MathTests/testAdd()", files_count: 2}
            ], 2} = Evidence.list_scopes(test_run)

    assert {[%{scope_id: "AppTests", files_count: 4}], 1} = Evidence.list_scopes(test_run, kind: "target")
  end

  test "reports a test's files by the narrowest scope that holds them", %{test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert Evidence.files(test_run, "AppTests", "MathTests", "testAdd()") == [
             %{path: "Sources/Math.swift", scope: "test", git_blob_id: ""},
             %{path: "Tests/MathTests.swift", scope: "test", git_blob_id: ""},
             %{path: "Sources/Bootstrap.swift", scope: "suite", git_blob_id: ""},
             %{path: "Sources/Text.swift", scope: "target", git_blob_id: ""}
           ]
  end

  test "names the tests covering a file, with the test case's stable id", %{project: project, test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert %{
             tests: [%{name: "resolves(a/b:)", suite_name: "MathTests", module_name: "AppTests", test_case_id: id}],
             suites: [],
             targets: ["AppTests"]
           } = Evidence.covering(test_run, "Sources/Text.swift")

    assert id == Tests.generate_test_case_id(project.id, "resolves(a/b:)", "AppTests", "MathTests")
    assert %{tests: [], suites: ["AppTests/MathTests"]} = Evidence.covering(test_run, "Sources/Bootstrap.swift")
  end

  test "keeps a module and a name that hold slashes apart, as a Bazel label does", %{project: project, test_run: test_run} do
    Evidence.record(test_run, %{
      paths: ["app/core/math.cc"],
      scopes: [
        %{kind: "test", module: "//app/core:tests", suite: "Math/Add", name: "adds(1/2)", files: [0]},
        %{kind: "suite", module: "//app/core:tests", suite: "Math/Add", name: "", files: [0]},
        %{kind: "target", module: "//app/core:tests", suite: "", name: "", files: [0]}
      ]
    })

    assert {[
              %{
                scope_id: "//app/core:tests/Math/Add/adds(1/2)",
                module_name: "//app/core:tests",
                suite_name: "Math/Add",
                name: "adds(1/2)"
              }
            ], 1} =
             Evidence.list_scopes(test_run)

    assert [%{path: "app/core/math.cc", scope: "test"}] =
             Evidence.files(test_run, "//app/core:tests", "Math/Add", "adds(1/2)")

    assert %{
             tests: [%{module_name: "//app/core:tests", suite_name: "Math/Add", name: "adds(1/2)", test_case_id: id}],
             suites: ["//app/core:tests/Math/Add"],
             targets: ["//app/core:tests"]
           } = Evidence.covering(test_run, "app/core/math.cc")

    assert id == Tests.generate_test_case_id(project.id, "adds(1/2)", "//app/core:tests", "Math/Add")
  end

  test "stores the lines a scope ran, and none where the client knew only the file", %{test_run: test_run} do
    Evidence.record(test_run, %{
      paths: ["Sources/Math.swift", "Sources/Text.swift"],
      scopes: [
        %{
          kind: "test",
          module: "AppTests",
          suite: "MathTests",
          name: "testAdd()",
          files: [0, 1],
          lines: [[3, 5, 9, 9], []]
        },
        %{kind: "target", module: "AppTests", suite: "", name: "", files: [0], lines: [[9, 3, -1, 2, 7]]}
      ]
    })

    rows =
      Tuist.ClickHouseRepo.all(
        from(f in Tuist.Tests.CoverageFile,
          where: f.test_run_id == ^test_run.id and f.scope_kind != "run",
          select: {f.scope_kind, f.path, f.line_numbers, f.covered_lines},
          order_by: [f.scope_kind, f.path]
        )
      )

    assert rows == [
             {"target", "Sources/Math.swift", [], 0},
             {"test", "Sources/Math.swift", [3, 4, 5, 9], 4},
             {"test", "Sources/Text.swift", [], 0}
           ]
  end

  test "a later report replaces the shard's earlier one", %{test_run: test_run} do
    Evidence.record(test_run, @evidence)

    Evidence.record(test_run, %{
      paths: ["Sources/Math.swift"],
      scopes: [%{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0]}]
    })

    assert %{tests: 1, files: 1} = Evidence.summary(test_run)
  end

  test "stores and reports nothing while the account's coverage flag is off", %{test_run: test_run} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)
    Evidence.record(test_run, @evidence)
    assert Evidence.summary(test_run) == nil

    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> true end)
    assert Evidence.summary(test_run) == nil

    Evidence.record(test_run, @evidence)
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)
    assert Evidence.summary(test_run) == nil
  end

  test "never reaches the run's coverage", %{project: project, test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert Coverage.run_summary(project.id, test_run.id) == nil
    assert Evidence.summary(%{test_run | id: UUIDv7.generate()}) == nil
  end
end
