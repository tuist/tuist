defmodule Tuist.Tests.Coverage.EvidenceTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.CoverageFile
  alias TuistTestSupport.Fixtures.CoverageFixtures
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

  @test_modules [
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

  setup do
    project = ProjectsFixtures.project_fixture()
    {:ok, test} = RunsFixtures.test_fixture(project_id: project.id, test_modules: @test_modules)
    %{project: project, test_run: test}
  end

  test "stores each scope's files, leaving out unknown kinds and files the report does not have", %{test_run: test_run} do
    Evidence.record(test_run, @evidence)

    rows = test_run |> CoverageFixtures.evidence_rows() |> Enum.map(&{&1.scope_kind, &1.scope_id, &1.path})
    add = Evidence.test_scope_id("AppTests", "MathTests", "testAdd()")
    resolves = Evidence.test_scope_id("AppTests", "MathTests", "resolves(a/b:)")
    suite = Evidence.suite_scope_id("AppTests", "MathTests")

    assert Enum.sort(rows) ==
             Enum.sort([
               {"suite", suite, "Sources/Bootstrap.swift"},
               {"target", "AppTests", "Sources/Bootstrap.swift"},
               {"target", "AppTests", "Sources/Math.swift"},
               {"target", "AppTests", "Sources/Text.swift"},
               {"target", "AppTests", "Tests/MathTests.swift"},
               {"test", add, "Sources/Math.swift"},
               {"test", add, "Tests/MathTests.swift"},
               {"test", resolves, "Sources/Math.swift"},
               {"test", resolves, "Sources/Text.swift"},
               {"test", resolves, "Tests/MathTests.swift"}
             ])
  end

  test "keeps a module and a name that hold slashes apart, as a Bazel label does", %{test_run: test_run} do
    Evidence.record(test_run, %{
      paths: ["app/core/math.cc"],
      scopes: [
        %{kind: "test", module: "//app/core:tests", suite: "Math/Add", name: "adds(1/2)", files: [0]},
        %{kind: "suite", module: "//app/core:tests", suite: "Math/Add", name: "", files: [0]},
        %{kind: "target", module: "//app/core:tests", suite: "", name: "", files: [0]}
      ]
    })

    assert test_run |> CoverageFixtures.evidence_rows() |> Enum.map(&{&1.scope_kind, &1.scope_id}) |> Enum.sort() == [
             {"suite", Evidence.suite_scope_id("//app/core:tests", "Math/Add")},
             {"target", "//app/core:tests"},
             {"test", Evidence.test_scope_id("//app/core:tests", "Math/Add", "adds(1/2)")}
           ]

    assert Evidence.test_scope_id("//app/core:tests", "Math/Add", "adds(1/2)") != "//app/core:tests/Math/Add/adds(1/2)"
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
        from(f in CoverageFile,
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

  test "keeps only the path of files whose lines exceed the report's line budget", %{test_run: test_run} do
    Evidence.record(
      test_run,
      %{
        paths: ["Sources/Math.swift", "Sources/Text.swift", "Sources/Bootstrap.swift"],
        scopes: [
          %{
            kind: "test",
            module: "AppTests",
            suite: "MathTests",
            name: "testAdd()",
            files: [0, 1, 2],
            # Repeating a range adds nothing: Math.swift costs 6 lines of the budget of 10.
            lines: [List.flatten(List.duplicate([1, 6], 1_000)), [1, 5], [1, 4]]
          }
        ]
      },
      nil,
      line_budget: 10
    )

    rows =
      Tuist.ClickHouseRepo.all(
        from(f in CoverageFile,
          where: f.test_run_id == ^test_run.id and f.scope_kind != "run",
          select: {f.path, f.line_numbers},
          order_by: f.path
        )
      )

    assert rows == [
             {"Sources/Bootstrap.swift", [1, 2, 3, 4]},
             {"Sources/Math.swift", [1, 2, 3, 4, 5, 6]},
             {"Sources/Text.swift", []}
           ]
  end

  test "names the tests a report holds evidence of their own for, as record/3 stores them", %{project: project} do
    # `outOfRange()` points only at a path the report does not have, so
    # nothing is stored for it; suites, targets and unknown kinds are no test's.
    assert Evidence.tests_with_evidence(project.id, @evidence) ==
             MapSet.new([{"testAdd()", "AppTests", "MathTests"}, {"resolves(a/b:)", "AppTests", "MathTests"}])

    assert Evidence.tests_with_evidence(project.id, nil) == MapSet.new()
  end

  test "flags the test case runs of the tests the report holds evidence of their own for", %{project: project} do
    modules = [
      %{
        name: "AppTests",
        status: "success",
        duration: 10,
        test_cases: [
          %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5},
          %{name: "testNone()", test_suite_name: "MathTests", status: "success", duration: 5}
        ]
      }
    ]

    evidence = %{
      paths: ["Sources/Math.swift"],
      scopes: [%{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0], lines: [[3, 5]]}]
    }

    {:ok, measured} =
      RunsFixtures.test_fixture(project_id: project.id, test_modules: modules, coverage_evidence: evidence)

    flags =
      Tuist.ClickHouseRepo.all(
        from(r in Tuist.Tests.TestCaseRun,
          where: r.test_run_id == ^measured.id,
          order_by: r.name,
          select: {r.name, r.has_coverage_evidence}
        )
      )

    assert flags == [{"testAdd()", true}, {"testNone()", false}]
  end

  test "a report's rows share one timestamp, later than the shard's earlier report", %{test_run: test_run} do
    Evidence.record(test_run, @evidence)

    Evidence.record(test_run, %{
      paths: ["Sources/Math.swift"],
      scopes: [%{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0]}]
    })

    [first, second] =
      test_run
      |> CoverageFixtures.evidence_rows()
      |> Enum.group_by(& &1.inserted_at)
      |> Enum.sort_by(&elem(&1, 0), NaiveDateTime)
      |> Enum.map(&elem(&1, 1))

    assert length(first) == 10
    assert [%{scope_kind: "test", path: "Sources/Math.swift"}] = second
  end

  test "stores nothing while the account's coverage flag is off", %{test_run: test_run} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)
    Evidence.record(test_run, @evidence)

    assert CoverageFixtures.evidence_rows(test_run) == []
  end

  test "never reaches the run's coverage", %{project: project, test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert CoverageFixtures.run_summary(project.id, test_run.id) == nil
  end
end
