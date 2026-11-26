defmodule Tuist.Tests.Coverage.EvidenceTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.TestCaseRun
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

  test "names the tests a report recorded only as overlapping another", %{project: project} do
    evidence = %{
      "paths" => [],
      "scopes" => [],
      "overlapped_tests" => [
        %{"module" => "AppTests", "suite" => "SwiftTests", "name" => "overlaps()"},
        %{"module" => "AppTests", "name" => "outsideASuite()"},
        %{"module" => "", "suite" => "SwiftTests", "name" => "noModule()"},
        "not a test"
      ]
    }

    assert Evidence.overlapped_tests(project.id, evidence) ==
             MapSet.new([{"overlaps()", "AppTests", "SwiftTests"}, {"outsideASuite()", "AppTests", ""}])

    assert Evidence.overlapped_tests(project.id, %{paths: [], scopes: []}) == MapSet.new()
    assert Evidence.overlapped_tests(project.id, nil) == MapSet.new()
  end

  test "records on each test case run whether the report holds the test's own evidence or its overlap", %{
    project: project
  } do
    modules = [
      %{
        name: "AppTests",
        status: "success",
        duration: 10,
        test_cases: [
          %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5},
          %{name: "testNone()", test_suite_name: "MathTests", status: "success", duration: 5},
          %{name: "testOverlap()", test_suite_name: "MathTests", status: "success", duration: 5}
        ]
      }
    ]

    evidence = %{
      paths: ["Sources/Math.swift"],
      scopes: [%{kind: "test", module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0], lines: [[3, 5]]}],
      overlapped_tests: [%{module: "AppTests", suite: "MathTests", name: "testOverlap()"}]
    }

    {:ok, measured} =
      RunsFixtures.test_fixture(project_id: project.id, test_modules: modules, coverage_evidence: evidence)

    flags =
      Tuist.ClickHouseRepo.all(
        from(r in TestCaseRun,
          where: r.test_run_id == ^measured.id,
          order_by: r.name,
          select: {r.name, r.coverage_evidence}
        )
      )

    assert flags == [{"testAdd()", "own"}, {"testNone()", "none"}, {"testOverlap()", "overlapped"}]
  end

  describe "evidence the client uploaded" do
    @modules [
      %{
        name: "AppTests",
        status: "success",
        duration: 10,
        test_cases: [
          %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5},
          %{name: "testNone()", test_suite_name: "MathTests", status: "success", duration: 5},
          %{name: "testOverlap()", test_suite_name: "MathTests", status: "success", duration: 5}
        ]
      }
    ]

    @tag :tmp_dir
    test "is read while the run is created, each scope naming its files by path", %{project: project, tmp_dir: tmp_dir} do
      lines = [
        %{
          kind: "test",
          module: "AppTests",
          suite: "MathTests",
          name: "testAdd()",
          files: ["Sources/Math.swift"],
          lines: [[3, 5]]
        },
        %{
          kind: "target",
          module: "AppTests",
          suite: "",
          name: "",
          files: ["Sources/Boot.swift", "Sources/Math.swift"],
          lines: [[1, 1], [3, 6]]
        }
      ]

      upload = deflated(tmp_dir, Enum.map_join(lines, "\n", &JSON.encode!/1) <> "\n")

      serve(upload)

      {:ok, run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: @modules,
          coverage_evidence: %{
            storage_key: "key",
            overlapped_tests: [%{module: "AppTests", suite: "MathTests", name: "testOverlap()"}],
            status: "collected"
          }
        )

      rows = run |> CoverageFixtures.evidence_rows() |> Enum.map(&{&1.scope_kind, &1.path, &1.line_numbers})

      assert Enum.sort(rows) == [
               {"target", "Sources/Boot.swift", [1]},
               {"target", "Sources/Math.swift", [3, 4, 5, 6]},
               {"test", "Sources/Math.swift", [3, 4, 5]}
             ]

      assert case_flags(run) == [{"testAdd()", "own"}, {"testNone()", "none"}, {"testOverlap()", "overlapped"}]
      assert run.coverage_evidence_status == "collected"
      assert [] = Path.wildcard(Path.join(System.tmp_dir!(), "coverage_evidence_*"))
    end

    @tag :tmp_dir
    test "that can't be read leaves the run without evidence, its status failed", %{project: project, tmp_dir: tmp_dir} do
      upload = deflated(tmp_dir, ~s({"kind":"test","module":"AppTests"}\nnot json\n))

      truncated = Path.join(tmp_dir, "truncated.deflate")

      lines =
        Enum.map_join(
          1..2_000,
          "\n",
          &JSON.encode!(%{kind: "target", module: "AppTests", files: ["Sources/#{&1}.swift"]})
        )

      compressed = :zlib.zip(lines <> "\n")
      File.write!(truncated, binary_part(compressed, 0, div(byte_size(compressed), 2)))

      for serve <- [
            fn -> serve(upload) end,
            fn -> serve(truncated) end,
            fn -> expect(Tuist.Storage, :get_object_size, fn _key, _account -> {:error, :not_found} end) end
          ] do
        serve.()

        {:ok, run} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            test_modules: @modules,
            coverage_evidence: %{storage_key: "key", status: "collected"}
          )

        assert CoverageFixtures.evidence_rows(run) == []
        assert Enum.all?(case_flags(run), &(elem(&1, 1) == "none"))
        assert run.coverage_evidence_status == "failed"
      end
    end

    @tag :tmp_dir
    test "reads a scope spread over many reads, and none larger than the inline request may be", %{
      project: project,
      tmp_dir: tmp_dir
    } do
      # Past one 64 KB read, then past the 50 MB a whole inline request may hold.
      for {padding, status} <- [{200_000, "collected"}, {50_000_000, "failed"}] do
        scope = %{
          kind: "test",
          module: "AppTests",
          suite: "MathTests",
          name: "testAdd()",
          files: ["Sources/Math.swift"],
          lines: [[3, 5]],
          padding: String.duplicate("x", padding)
        }

        upload = deflated(tmp_dir, JSON.encode!(scope) <> "\n")

        serve(upload)

        {:ok, run} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            test_modules: @modules,
            coverage_evidence: %{storage_key: "key", status: "collected"}
          )

        assert run.coverage_evidence_status == status

        assert run |> CoverageFixtures.evidence_rows() |> Enum.map(&{&1.path, &1.line_numbers}) ==
                 if(status == "collected", do: [{"Sources/Math.swift", [3, 4, 5]}], else: [])
      end
    end

    test "past 250 MB compressed is refused before it is fetched", %{project: project} do
      # Sized past the limit: nothing is downloaded.
      expect(Tuist.Storage, :get_object_size, fn "key", _account -> {:ok, 250_000_001} end)
      reject(&Tuist.Storage.stream_object/2)

      {:ok, run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: @modules,
          coverage_evidence: %{storage_key: "key", status: "collected"}
        )

      assert run.coverage_evidence_status == "failed"
    end

    test "sized within 250 MB but replaced since is never fetched past that", %{project: project} do
      chunk = :binary.copy("x", 1_000_000)
      pulled = :counters.new(1, [])
      expect(Tuist.Storage, :get_object_size, fn "key", _account -> {:ok, 1_000} end)

      expect(Tuist.Storage, :stream_object, fn "key", _account ->
        Stream.repeatedly(fn ->
          :counters.add(pulled, 1, 1)
          chunk
        end)
      end)

      {:ok, run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: @modules,
          coverage_evidence: %{storage_key: "key", status: "collected"}
        )

      assert run.coverage_evidence_status == "failed"
      assert :counters.get(pulled, 1) == 251
      assert [] = Path.wildcard(Path.join(System.tmp_dir!(), "coverage_evidence_*"))
    end

    defp serve(upload) do
      expect(Tuist.Storage, :get_object_size, fn _key, _account -> {:ok, File.stat!(upload).size} end)
      expect(Tuist.Storage, :stream_object, fn _key, _account -> File.stream!(upload, 65_536) end)
    end

    defp deflated(tmp_dir, ndjson) do
      z = :zlib.open()
      :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
      path = Path.join(tmp_dir, "evidence.ndjson.deflate")
      File.write!(path, [:zlib.deflate(z, ndjson), :zlib.deflate(z, "", :finish)])
      :zlib.close(z)
      path
    end

    defp case_flags(run) do
      Tuist.ClickHouseRepo.all(
        from(r in TestCaseRun,
          where: r.test_run_id == ^run.id,
          order_by: r.name,
          select: {r.name, r.coverage_evidence}
        )
      )
    end
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

  test "stores a report of several chunks as one part", %{test_run: test_run} do
    paths = for i <- 1..12_000, do: "Sources/File#{i}.swift"

    Evidence.record(test_run, %{
      paths: paths,
      scopes: [%{kind: "target", module: "AppTests", files: Enum.to_list(0..11_999)}]
    })

    assert IngestRepo.query!(
             "SELECT uniqExact(_part), count() FROM coverage_files WHERE project_id = {p:Int64} AND test_run_id = {id:UUID}",
             %{"p" => test_run.project_id, "id" => test_run.id}
           ).rows == [[1, 12_000]]
  end

  test "stores nothing for a project whose build system has no coverage" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_modules: @test_modules)
    Evidence.record(test_run, @evidence)

    assert CoverageFixtures.evidence_rows(test_run) == []
  end

  test "never reaches the run's coverage", %{project: project, test_run: test_run} do
    Evidence.record(test_run, @evidence)

    assert CoverageFixtures.run_summary(project.id, test_run.id) == nil
  end

  test "reads whether a run collected evidence, the strongest of its shards'" do
    assert Evidence.status(nil) == ""
    assert Evidence.status(%{paths: [], scopes: []}) == ""
    assert Evidence.status(%{"status" => "not_linked"}) == "not_linked"
    assert Evidence.status(%{status: "unexpected"}) == ""

    assert Evidence.merge_status("not_linked", "collected") == "collected"
    assert Evidence.merge_status("", "failed") == "failed"
    assert Evidence.merge_status("", "") == ""
  end
end
