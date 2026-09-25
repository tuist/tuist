defmodule Tuist.Tests.CoverageTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{account: account, project: project}
  end

  defp file(path, blob, targets, lines, functions \\ []) do
    %{
      path: path,
      git_blob_id: blob,
      targets: targets,
      covered_lines: Enum.count(lines, fn {_line, count} -> count > 0 end),
      executable_lines: length(lines),
      line_numbers: Enum.map(lines, &elem(&1, 0)),
      execution_counts: Enum.map(lines, &elem(&1, 1)),
      functions: functions
    }
  end

  defp coverage(files, opts \\ []) do
    %{partial: Keyword.get(opts, :partial, false), files: files}
  end

  defp add do
    file(
      "Sources/Calculator/Add.swift",
      "add1",
      ["Calculator", "CalculatorTests"],
      [{2, 3}, {3, 0}, {4, 0}, {6, 1}, {7, 0}],
      [%{name: "add(_:_:)", line_number: 2, execution_count: 3, covered_lines: 2, executable_lines: 5}]
    )
  end

  defp untested, do: file("Sources/Calculator/Untested.swift", "untested1", ["Calculator"], [{2, 0}, {3, 0}])
  defp formatter, do: file("Sources/Formatter/Formatter.swift", "formatter1", ["Formatter"], [{1, 2}, {2, 2}])

  defp create_test(project, account, attrs) do
    Tests.create_test(
      Map.merge(
        %{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration: 1000,
          status: "success",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: []
        },
        attrs
      )
    )
  end

  # The totals the coverage trend reads.
  defp published_totals(project, test) do
    ClickHouseRepo.one(
      from(c in CoverageRun,
        where: c.project_id == ^project.id and c.test_run_id == ^test.id,
        group_by: c.test_run_id,
        select: %{
          covered_lines: fragment("argMax(?, ?)", c.covered_lines, c.version),
          executable_lines: fragment("argMax(?, ?)", c.executable_lines, c.version),
          partial: fragment("argMax(?, ?)", c.partial, c.version)
        }
      )
    )
  end

  describe "create_test/1 with xcode_coverage" do
    test "stores every observed file with its lines and the run's totals", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add(), untested(), formatter()])})

      assert CoverageFixtures.run_summary(project.id, test.id) == %{covered_lines: 4, executable_lines: 9, partial: false}
      assert published_totals(project, test) == %{covered_lines: 4, executable_lines: 9, partial: false}

      # A file compiled into several targets counts towards each of them.
      assert project.id
             |> CoverageFixtures.targets_for_run(test.id)
             |> Enum.map(&{&1.name, &1.files_count, &1.covered_lines, &1.executable_lines}) ==
               [{"Calculator", 2, 2, 7}, {"CalculatorTests", 1, 2, 5}, {"Formatter", 1, 2, 2}]

      {files, count} = Coverage.list_files(project.id, test.id, 1, 20)
      assert count == 3

      assert Enum.map(files, & &1.path) == [
               "Sources/Calculator/Untested.swift",
               "Sources/Calculator/Add.swift",
               "Sources/Formatter/Formatter.swift"
             ]

      assert Enum.map(files, & &1.git_blob_id) == ["untested1", "add1", "formatter1"]
    end

    test "describes one file's lines, uncovered ranges and functions", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})

      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")

      assert detail.git_blob_id == "add1"
      assert detail.targets == ["Calculator", "CalculatorTests"]
      assert {detail.covered_lines, detail.executable_lines} == {2, 5}
      # Lines 3 and 4 run together; 5 is not executable, so 7 starts its own range after 6 ran.
      assert detail.uncovered_ranges == [{3, 4}, {7, 7}]
      assert [%{name: "add(_:_:)", execution_count: 3}] = detail.functions
      assert Coverage.file_detail(project.id, test.id, "Missing.swift") == nil
    end

    test "keeps the report's counts for a file without line data", %{project: project, account: account} do
      counts_only = %{
        file("Sources/Calculator/Legacy.swift", "legacy1", ["Calculator"], [])
        | covered_lines: 8,
          executable_lines: 10
      }

      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([counts_only])})

      assert {[%{covered_lines: 8, executable_lines: 10}], 1} = Coverage.list_files(project.id, test.id, 1, 20)

      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Legacy.swift")
      assert {detail.covered_lines, detail.executable_lines} == {8, 10}
      # Which lines ran is unknown, which is not the same as none being uncovered.
      assert detail.uncovered_ranges == nil
    end

    test "leaves a run without coverage untouched", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{})

      assert CoverageFixtures.run_summary(project.id, test.id) == nil
      assert published_totals(project, test) == nil
      assert CoverageFixtures.targets_for_run(project.id, test.id) == []
    end
  end

  describe "coverage streamed to a file" do
    @tag :tmp_dir
    test "publishes the same rows and totals as the inline form, from string-keyed lines", %{
      project: project,
      account: account,
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "coverage.ndjson")

      lines =
        Enum.map([add(), untested(), formatter()], fn file ->
          file
          |> Map.update!(:functions, fn functions ->
            Enum.map(functions, &Map.new(&1, fn {k, v} -> {Atom.to_string(k), v} end))
          end)
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
          |> JSON.encode!()
        end)

      File.write!(path, Enum.join(lines, "\n") <> "\n")

      {:ok, test} = create_test(project, account, %{xcode_coverage: %{path: path, partial: false}})

      assert CoverageFixtures.run_summary(project.id, test.id) == %{covered_lines: 4, executable_lines: 9, partial: false}
      assert published_totals(project, test) == %{covered_lines: 4, executable_lines: 9, partial: false}
      {files, 3} = Coverage.list_files(project.id, test.id, 1, 20)
      assert Enum.map(files, & &1.git_blob_id) == ["untested1", "add1", "formatter1"]

      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert Enum.map(detail.functions, & &1.name) == ["add(_:_:)"]
    end

    @tag :tmp_dir
    test "merges a streamed shard with the shards already reported", %{
      project: project,
      account: account,
      tmp_dir: tmp_dir
    } do
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
      shard = fn lines, index -> %{shard_plan_id: plan.id, shard_index: index, xcode_coverage: coverage(lines)} end

      {:ok, test} =
        create_test(
          project,
          account,
          shard.([file("Sources/Calculator/Add.swift", "add1", ["Calculator"], [{2, 3}, {3, 0}])], 0)
        )

      path = Path.join(tmp_dir, "shard1.ndjson")

      File.write!(
        path,
        JSON.encode!(
          Map.new(file("Sources/Calculator/Add.swift", "add1", ["Calculator"], [{2, 0}, {3, 1}, {4, 0}]), fn {k, v} ->
            {Atom.to_string(k), v}
          end)
        ) <>
          "\n"
      )

      {:ok, stored} = Tests.get_test(test.id)
      Coverage.publish(stored, Coverage.rows(project.id, %{path: path, partial: false}), 1, 2)

      # Lines 2 and 3 covered across shards; 2, 3, 4 executable.
      assert CoverageFixtures.run_summary(project.id, test.id) == %{covered_lines: 2, executable_lines: 3, partial: false}
      assert published_totals(project, test) == %{covered_lines: 2, executable_lines: 3, partial: false}
    end
  end

  describe "what measured the coverage" do
    test "is recorded on every row with the run's scheme and the repository's object format", %{
      project: project,
      account: account
    } do
      sha1 = String.duplicate("a", 40)
      tracked = file("Sources/Calculator/Add.swift", sha1, ["Calculator"], [{2, 3}, {3, 0}])
      untracked = file("Sources/Calculator/Generated.swift", nil, ["Calculator"], [{1, 1}])
      outside = file("/tmp/DerivedSources/Outside.swift", sha1, ["Calculator"], [{1, 1}])

      {:ok, test} =
        create_test(project, account, %{
          scheme: "Calculator",
          xcode_version: "26.3",
          xcode_coverage: coverage([tracked, untracked, outside])
        })

      assert ClickHouseRepo.one(
               from(c in CoverageRun,
                 where: c.test_run_id == ^test.id,
                 select: %{
                   build_system: c.build_system,
                   coverage_tool: c.coverage_tool,
                   coverage_tool_version: c.coverage_tool_version,
                   git_object_format: c.git_object_format,
                   scheme: c.scheme
                 }
               )
             ) == %{
               build_system: "xcode",
               coverage_tool: "xccov",
               coverage_tool_version: "26.3",
               git_object_format: "sha1",
               scheme: "Calculator"
             }

      assert ClickHouseRepo.all(
               from(f in CoverageFile,
                 where: f.test_run_id == ^test.id,
                 order_by: f.path,
                 select: {f.path, f.in_repository, f.build_system, f.scope_kind, f.scope_id, f.evidence_kind}
               )
             ) == [
               {"/tmp/DerivedSources/Outside.swift", false, "xcode", "run", "", "observed"},
               {"Sources/Calculator/Add.swift", true, "xcode", "run", "", "observed"},
               {"Sources/Calculator/Generated.swift", false, "xcode", "run", "", "observed"}
             ]
    end

    test "reports a SHA-256 repository and no format when nothing was tracked", %{project: project, account: account} do
      sha256 = String.duplicate("b", 64)

      {:ok, tracked} =
        create_test(project, account, %{
          xcode_coverage: coverage([file("Sources/A.swift", sha256, ["A"], [{1, 1}])])
        })

      {:ok, untracked} =
        create_test(project, account, %{xcode_coverage: coverage([file("Sources/A.swift", nil, ["A"], [{1, 1}])])})

      formats =
        ClickHouseRepo.all(
          from(c in CoverageRun,
            where: c.test_run_id in ^[tracked.id, untracked.id],
            select: {c.test_run_id, c.git_object_format}
          )
        )

      assert Map.new(formats) == %{tracked.id => "sha256", untracked.id => ""}
    end
  end

  describe "test code" do
    test "is stored but left out of the totals, targets and files", %{project: project, account: account} do
      test_file =
        "Tests/CalculatorTests/CalculatorTests.swift"
        |> file("tests1", ["CalculatorTests"], [{1, 1}, {2, 1}, {3, 1}])
        |> Map.put(:is_test, true)

      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add(), test_file])})

      assert %{covered_lines: 2, executable_lines: 5} = CoverageFixtures.run_summary(project.id, test.id)
      assert %{covered_lines: 2, executable_lines: 5} = published_totals(project, test)

      assert project.id |> CoverageFixtures.targets_for_run(test.id) |> Enum.map(& &1.name) == [
               "Calculator",
               "CalculatorTests"
             ]

      assert {[%{path: "Sources/Calculator/Add.swift"}], 1} = Coverage.list_files(project.id, test.id, 1, 20)
      assert Coverage.file_detail(project.id, test.id, "Tests/CalculatorTests/CalculatorTests.swift") == nil
    end
  end

  describe "excluded paths" do
    defp generated, do: file("Sources/Client/Client.generated.swift", "client1", ["Calculator"], [{1, 0}, {2, 0}, {3, 0}])

    test "are stored but left out of the totals, targets, files and line counts", %{project: project, account: account} do
      {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["**/*.generated.swift"]})
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add(), generated()])})

      assert %{covered_lines: 2, executable_lines: 5} = CoverageFixtures.run_summary(project.id, test.id)
      assert %{covered_lines: 2, executable_lines: 5} = published_totals(project, test)
      assert {[%{path: "Sources/Calculator/Add.swift"}], 1} = Coverage.list_files(project.id, test.id, 1, 20)

      assert [%{name: "Calculator", files_count: 1}, %{name: "CalculatorTests"}] =
               CoverageFixtures.targets_for_run(project.id, test.id)

      assert Coverage.line_counts(project.id, test.id, ["Sources/Client/Client.generated.swift"]) == %{}
      assert %{executable_lines: 3} = Coverage.file_detail(project.id, test.id, "Sources/Client/Client.generated.swift")
    end

    test "are the project's own, nothing being excluded by default", %{project: project, account: account} do
      {:ok, default} = create_test(project, account, %{xcode_coverage: coverage([add(), generated()])})
      assert %{covered_lines: 2, executable_lines: 8} = CoverageFixtures.run_summary(project.id, default.id)

      {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["Sources/Formatter/**"]})
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add(), generated(), formatter()])})

      assert %{covered_lines: 2, executable_lines: 8} = CoverageFixtures.run_summary(project.id, test.id)
      assert %{covered_lines: 2, executable_lines: 8} = published_totals(project, test)
      assert %{covered_lines: 4, executable_lines: 10} = CoverageFixtures.run_summary(project.id, test.id, excluded: nil)
    end

    test "republish the retained runs' totals when they change", %{project: project, account: account} do
      {:ok, first} = create_test(project, account, %{xcode_coverage: coverage([add(), generated()])})
      {:ok, second} = create_test(project, account, %{xcode_coverage: coverage([formatter(), generated()])})
      {:ok, only_generated} = create_test(project, account, %{xcode_coverage: coverage([generated()])})
      assert %{executable_lines: 3} = published_totals(project, only_generated)

      {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["Sources/Calculator/**"]})

      first_batch = Coverage.recompute_totals(project.id, batch_size: 2)
      assert is_binary(first_batch)
      assert Coverage.recompute_totals(project.id, batch_size: 2, after: first_batch) == nil

      assert published_totals(project, first) == %{covered_lines: 0, executable_lines: 3, partial: false}
      assert published_totals(project, second) == %{covered_lines: 2, executable_lines: 5, partial: false}
      assert published_totals(project, only_generated) == %{covered_lines: 0, executable_lines: 3, partial: false}

      {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["Sources/**"]})
      assert Coverage.recompute_totals(project.id, batch_size: 10) == nil

      # A run with nothing left to count leaves the trend.
      assert CoverageFixtures.published_totals(project.id, [first.id, second.id, only_generated.id]) == %{}
      assert %{partial: false, executable_lines: 0} = published_totals(project, first)
    end

    test "leave a report published after a recompute in charge", %{project: project, account: account} do
      shard_plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
      sharded = %{shard_plan_id: shard_plan.id, shard_index: 0, xcode_coverage: coverage([add(), generated()])}
      {:ok, test} = create_test(project, account, sharded)

      {:ok, project} = Projects.update_project(project, %{coverage_excluded_path_globs: ["**/*.generated.swift"]})
      assert Coverage.recompute_totals(project.id, batch_size: 10) == nil
      assert published_totals(project, test) == %{covered_lines: 2, executable_lines: 5, partial: true}

      {:ok, _test} = create_test(project, account, %{sharded | shard_index: 1, xcode_coverage: coverage([untested()])})
      assert published_totals(project, test) == %{covered_lines: 2, executable_lines: 7, partial: false}
    end
  end

  describe "the xcode_coverage feature flag" do
    test "drops the coverage of an account that does not have it", %{project: project, account: account} do
      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})

      assert CoverageFixtures.run_summary(project.id, test.id) == nil
      assert {[], 0} = Coverage.list_files(project.id, test.id, 1, 20)
    end
  end

  describe "partial runs" do
    test "are marked partial and never borrow coverage from earlier runs", %{project: project, account: account} do
      {:ok, _full} = create_test(project, account, %{xcode_coverage: coverage([add(), untested(), formatter()])})

      partial_add = file("Sources/Calculator/Add.swift", "add1", ["Calculator"], [{2, 1}, {3, 0}, {4, 0}, {6, 0}, {7, 0}])
      {:ok, partial} = create_test(project, account, %{xcode_coverage: coverage([partial_add], partial: true)})

      assert CoverageFixtures.run_summary(project.id, partial.id) == %{
               covered_lines: 1,
               executable_lines: 5,
               partial: true
             }

      assert published_totals(project, partial) == %{covered_lines: 1, executable_lines: 5, partial: true}

      assert {[%{path: "Sources/Calculator/Add.swift", covered_lines: 1}], 1} =
               Coverage.list_files(project.id, partial.id, 1, 20)
    end
  end

  describe "sharded runs" do
    # Another shard ran other tests over the same file, and skipped some on purpose.
    defp other_shard do
      coverage(
        [file("Sources/Calculator/Add.swift", "add1", ["CalculatorTests"], [{2, 1}, {3, 5}, {4, 0}, {6, 0}, {7, 0}])],
        partial: true
      )
    end

    test "merge the shards' lines and stay partial once any shard was", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})
      {:ok, stored} = Tests.get_test(test.id)

      Coverage.publish(stored, Coverage.rows(project.id, other_shard()), 1)

      assert CoverageFixtures.run_summary(project.id, test.id) == %{covered_lines: 3, executable_lines: 5, partial: true}
      assert published_totals(project, test) == %{covered_lines: 3, executable_lines: 5, partial: true}

      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert Enum.take(detail.lines, 2) == [{2, 4}, {3, 5}]
      assert detail.uncovered_ranges == [{4, 4}, {7, 7}]
      assert detail.targets == ["Calculator", "CalculatorTests"]
    end

    test "show a function's coverage only when at most one shard covered it", %{project: project, account: account} do
      function = fn covered ->
        %{name: "add(_:_:)", line_number: 2, execution_count: covered, covered_lines: covered, executable_lines: 2}
      end

      shard = fn lines, covered ->
        coverage([file("Sources/Calculator/Add.swift", "add1", ["Calculator"], lines, [function.(covered)])])
      end

      {:ok, test} = create_test(project, account, %{xcode_coverage: shard.([{2, 1}, {3, 0}], 1)})
      {:ok, stored} = Tests.get_test(test.id)

      # A shard that ran none of the function leaves the other shard's count exact.
      Coverage.publish(stored, Coverage.rows(project.id, shard.([{2, 0}, {3, 0}], 0)), 1)
      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert [%{covered_lines: 1, executable_lines: 2, execution_count: 1}] = detail.functions

      # Two shards each covered one line: 1/2 twice could be the same line or both.
      Coverage.publish(stored, Coverage.rows(project.id, shard.([{2, 0}, {3, 1}], 1)), 1)
      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert {detail.covered_lines, detail.executable_lines} == {2, 2}
      assert [%{covered_lines: nil, executable_lines: 2, execution_count: 2}] = detail.functions
    end

    test "stay out of the trend until every shard of the plan reported coverage", %{project: project, account: account} do
      shard_plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
      sharded = %{shard_plan_id: shard_plan.id, shard_index: 0, xcode_coverage: coverage([add()])}

      {:ok, test} = create_test(project, account, sharded)

      # The other shard has not reported, or never will: its tests' coverage is missing.
      assert %{partial: true} = published_totals(project, test)

      {:ok, _test} =
        create_test(project, account, %{sharded | shard_index: 1, xcode_coverage: coverage([untested()])})

      assert published_totals(project, test) == %{covered_lines: 2, executable_lines: 7, partial: false}
    end

    test "publish a later shard's uploaded coverage and record its changed files", %{
      project: project,
      account: account
    } do
      shard_plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
      sharded = %{shard_plan_id: shard_plan.id, shard_index: 0}

      {:ok, test} = create_test(project, account, sharded)

      {:ok, _test} =
        create_test(
          project,
          account,
          Map.merge(%{sharded | shard_index: 1}, %{
            xcode_coverage_storage_key: "key",
            xcode_coverage_partial: true,
            changed_files: [
              %{path: "Sources/A.swift", status: "modified", git_blob_id: "blob", hunks: [%{start: 1, end: 2}]}
            ]
          })
        )

      assert_enqueued(
        worker: Tuist.Tests.Workers.PublishCoverageWorker,
        args: %{test_run_id: test.id, storage_key: "key", partial: true, shard_index: 1, expected_shards: 2}
      )

      assert [%{path: "Sources/A.swift", hunk_starts: [1], hunk_ends: [2]}] = CoverageFixtures.changed_files(test)
    end

    test "keep the most complete totals whatever order the reports land in", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})
      {:ok, stored} = Tests.get_test(test.id)
      Coverage.publish(stored, Coverage.rows(project.id, other_shard()), 1)

      # The first shard's totals, computed before the second shard reported, land last.
      [first_computation | _] =
        ClickHouseRepo.all(from(c in CoverageRun, where: c.test_run_id == ^test.id, order_by: [asc: c.version]))

      IngestRepo.insert_all(CoverageRun, [
        first_computation |> Map.from_struct() |> Map.delete(:__meta__) |> Map.put(:inserted_at, NaiveDateTime.utc_now())
      ])

      assert published_totals(project, test) == %{covered_lines: 3, executable_lines: 5, partial: true}
    end

    test "count a retried shard's report once", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})
      {:ok, stored} = Tests.get_test(test.id)

      Coverage.publish(stored, Coverage.rows(project.id, coverage([add()])), nil)

      detail = Coverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert Enum.take(detail.lines, 1) == [{2, 3}]
      assert [%{execution_count: 3}] = detail.functions
      assert {_files, 1} = Coverage.list_files(project.id, test.id, 1, 20)
      assert CoverageFixtures.run_summary(project.id, test.id) == %{covered_lines: 2, executable_lines: 5, partial: false}
    end
  end

  describe "percentage/2" do
    test "rounds to one decimal and survives a target with no executable lines" do
      assert Coverage.percentage(1, 3) == 33.3
      assert Coverage.percentage(0, 0) == 0.0
    end
  end

  describe "id_chunks/2" do
    test "keeps a chunk within what ClickHouse accepts as query parameters" do
      chunks = Coverage.id_chunks(Enum.to_list(1..5_000))

      assert Enum.concat(chunks) == Enum.to_list(1..5_000)
      assert Enum.all?(chunks, &(length(&1) <= 900))
    end

    test "leaves room for the parameters the query binds alongside the chunk" do
      chunks = Coverage.id_chunks(Enum.to_list(1..5_000), 200)

      assert Enum.concat(chunks) == Enum.to_list(1..5_000)
      assert Enum.all?(chunks, &(length(&1) + 200 <= 900))
    end

    test "never yields an empty chunk, whatever the query reserves" do
      assert Coverage.id_chunks([1, 2], 10_000) == [[1], [2]]
    end
  end
end
