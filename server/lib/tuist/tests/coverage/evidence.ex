defmodule Tuist.Tests.Coverage.Evidence do
  @moduledoc """
  Which files each test of a run executed: the evidence test selection plans
  over (a test is a candidate when a file it covered changed) and what says
  how much of a suite has evidence at all.

  The client's coverage observer records the coverage counters each test
  moved and reduces them to source files; the run reports them as
  `coverage_evidence` (`paths` once, and scopes referring to them by index).
  They are stored in `coverage_files` beside the run's own coverage, told
  apart by the scope:

  - `test`: what one test executed, `scope_id` `Module/Suite/name` (an empty
    suite for a test outside any): the fields a test case's stable id is made
    of (`Tuist.Tests.generate_test_case_id/4`), readable as they are;
  - `suite`: what ran around a suite's tests and belongs to none (class
    `setUp`, a one-time bootstrap), `scope_id` `Module/Suite`; every test of
    the suite may depend on it;
  - `target`: everything the target's processes executed, `scope_id` the
    module: the floor for each of its tests, and all there is for the tests
    nothing could be attributed to (Swift Testing running in parallel).

  Evidence rows hold a path and nothing else: no counts, and no blob, which
  is read off the run's own row for the path (`files/3`) or the commit's
  listing. Every reader of coverage filters on the `run` scope, so these rows
  never reach a total. Like the run's coverage, a report replaces the shard's
  earlier one: readers use each shard's latest.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.TestCaseRun

  @insert_chunk_size 5_000
  @scopes ~w(test suite target)

  @doc """
  Stores a run's evidence. `evidence` is the request's `coverage_evidence`,
  atom or string keyed; nil, or coverage turned off for the project, stores
  nothing.
  """
  def record(test, evidence, shard_index \\ nil)
  def record(_test, nil, _shard_index), do: :ok

  def record(%{id: test_run_id, project_id: project_id} = test, evidence, shard_index) do
    paths = evidence |> value(:paths, []) |> List.to_tuple()
    scopes = value(evidence, :scopes, [])

    if Coverage.enabled_for_project?(project_id) and tuple_size(paths) > 0 and scopes != [] do
      base = %{
        test_run_id: test_run_id,
        project_id: project_id,
        build_system: "xcode",
        shard_index: shard_index || 0,
        partial: false,
        evidence_kind: "observed",
        in_repository: true,
        git_blob_id: "",
        targets: [],
        is_test: false,
        git_commit_sha: Map.get(test, :git_commit_sha) || "",
        covered_lines: 0,
        executable_lines: 0,
        inserted_at: NaiveDateTime.utc_now()
      }

      scopes
      |> Stream.flat_map(&rows(&1, paths, base))
      |> Stream.chunk_every(@insert_chunk_size)
      |> Enum.each(&IngestRepo.insert_all(CoverageFile, &1))
    end

    :ok
  end

  @doc """
  How much of a run has evidence: the tests, suites and targets with some,
  the files they cover between them, the median and the largest number of
  files a test covers, and how many tests ran without any of their own
  (Swift Testing without the trait, or overlapping another test; their
  target's evidence is all they have). Nil when the run reported none.
  """
  def summary(%{id: test_run_id, project_id: project_id}) do
    with true <- Coverage.enabled_for_project?(project_id),
         {:ok, test_run_id} <- Ecto.UUID.cast(test_run_id),
         %{tests: _} = summary <-
           ClickHouseRepo.one(
             from(s in subquery(scopes_query(project_id, test_run_id)),
               select: %{
                 tests: fragment("countIf(? = 'test')", s.scope_kind),
                 suites: fragment("countIf(? = 'suite')", s.scope_kind),
                 targets: fragment("countIf(? = 'target')", s.scope_kind),
                 median_files_per_test:
                   fragment("toUInt32(ifNotFinite(quantileExactIf(0.5)(?, ? = 'test'), 0))", s.files_count, s.scope_kind),
                 max_files_per_test: fragment("toUInt32(maxIf(?, ? = 'test'))", s.files_count, s.scope_kind)
               }
             )
           ),
         true <- summary.tests + summary.suites + summary.targets > 0 do
      summary
      |> Map.put(:files, files_count(project_id, test_run_id))
      |> Map.put(:tests_without_evidence, tests_without_evidence(project_id, test_run_id))
    else
      _ -> nil
    end
  end

  @doc """
  The run's scopes of one kind (`test` by default) with how many files each
  covers, those covering most first, and their total count.
  """
  def list_scopes(%{id: test_run_id, project_id: project_id}, opts \\ []) do
    kind = Keyword.get(opts, :kind, "test")
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 50)
    query = from(s in subquery(scopes_query(project_id, test_run_id)), where: s.scope_kind == ^kind)

    scopes =
      ClickHouseRepo.all(
        from(s in query,
          order_by: [desc: s.files_count, asc: s.scope_id],
          limit: ^page_size,
          offset: ^((page - 1) * page_size)
        )
      )

    {scopes, ClickHouseRepo.aggregate(query, :count)}
  end

  @doc """
  The files a test's evidence holds, each with the scope that says so: the
  test's own, its suite's, or its target's floor. A file several scopes cover
  is reported by the narrowest. `git_blob_id` comes from the run's own
  coverage of the path, empty when the run has none.
  """
  def files(%{id: test_run_id, project_id: project_id}, module_name, suite_name, name) do
    ids = %{
      "test" => test_scope_id(module_name, suite_name || "", name),
      "suite" => suite_scope_id(module_name, suite_name || ""),
      "target" => module_name
    }

    blobs =
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.scope_kind == "run",
        group_by: f.path,
        select: %{path: f.path, git_blob_id: fragment("argMax(?, ?)", f.git_blob_id, f.inserted_at)}
      )

    rows =
      ClickHouseRepo.all(
        from(f in subquery(latest_rows_query(project_id, test_run_id)),
          left_join: b in subquery(blobs),
          on: b.path == f.path,
          where: f.scope_id in ^Map.values(ids),
          select: %{path: f.path, scope: f.scope_kind, scope_id: f.scope_id, git_blob_id: b.git_blob_id}
        )
      )

    rows
    |> Enum.filter(&(ids[&1.scope] == &1.scope_id))
    |> Enum.map(&Map.delete(&1, :scope_id))
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {_path, candidates} -> Enum.min_by(candidates, &scope_rank(&1.scope)) end)
    |> Enum.sort_by(&{scope_rank(&1.scope), &1.path})
  end

  @doc """
  The tests of the run whose own evidence holds `path`, by module, suite and
  name. Tests that only reach the file through their suite's or their
  target's evidence are not listed: `suites` and `targets` name those scopes
  so the caller can widen the answer.
  """
  def covering(%{id: test_run_id, project_id: project_id}, path) do
    rows =
      ClickHouseRepo.all(
        from(f in subquery(latest_rows_query(project_id, test_run_id)),
          where: f.path == ^path,
          select: %{scope_kind: f.scope_kind, scope_id: f.scope_id}
        )
      )

    by_kind = Enum.group_by(rows, & &1.scope_kind)

    %{
      tests: by_kind |> Map.get("test", []) |> Enum.map(&test_identity(project_id, &1.scope_id)) |> Enum.sort(),
      suites: by_kind |> Map.get("suite", []) |> Enum.map(& &1.scope_id) |> Enum.sort(),
      targets: by_kind |> Map.get("target", []) |> Enum.map(& &1.scope_id) |> Enum.sort()
    }
  end

  @doc """
  The module, suite and name a `test` scope id is made of, with the test
  case's stable id. A name keeps its own slashes: only the first two split.
  """
  def test_identity(project_id, scope_id) do
    [module_name, suite_name, name] =
      case String.split(scope_id, "/", parts: 3) do
        [module_name, suite_name, name] -> [module_name, suite_name, name]
        parts -> Enum.take(parts ++ ["", "", ""], 3)
      end

    %{
      test_case_id: Tests.generate_test_case_id(project_id, name, module_name, suite_name),
      module_name: module_name,
      suite_name: suite_name,
      name: name
    }
  end

  @doc false
  def test_scope_id(module_name, suite_name, name), do: "#{module_name}/#{suite_name}/#{name}"

  @doc false
  def suite_scope_id(module_name, suite_name), do: "#{module_name}/#{suite_name}"

  defp scope_rank("test"), do: 0
  defp scope_rank("suite"), do: 1
  defp scope_rank(_), do: 2

  defp tests_without_evidence(project_id, test_run_id) do
    with_evidence =
      from(f in subquery(latest_rows_query(project_id, test_run_id)),
        where: f.scope_kind == "test",
        select: f.scope_id
      )

    ClickHouseRepo.one(
      from(r in TestCaseRun,
        where: r.project_id == ^project_id and r.test_run_id == ^test_run_id and r.status != "skipped",
        where: fragment("concat(?, '/', ?, '/', ?)", r.module_name, r.suite_name, r.name) not in subquery(with_evidence),
        select: fragment("uniqExact(?, ?, ?)", r.module_name, r.suite_name, r.name)
      )
    ) || 0
  end

  defp files_count(project_id, test_run_id) do
    ClickHouseRepo.one(
      from(f in subquery(latest_rows_query(project_id, test_run_id)), select: fragment("uniqExact(?)", f.path))
    ) || 0
  end

  defp scopes_query(project_id, test_run_id) do
    from(f in subquery(latest_rows_query(project_id, test_run_id)),
      group_by: [f.scope_kind, f.scope_id],
      select: %{
        scope_kind: f.scope_kind,
        scope_id: f.scope_id,
        files_count: fragment("toUInt32(uniqExact(?))", f.path)
      }
    )
  end

  # Each shard's latest evidence report, as `Coverage` reads the run's own.
  defp latest_rows_query(project_id, test_run_id) do
    latest =
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.scope_kind in @scopes,
        group_by: f.shard_index,
        select: %{shard_index: f.shard_index, inserted_at: max(f.inserted_at)}
      )

    from(f in CoverageFile,
      join: l in subquery(latest),
      on: l.shard_index == f.shard_index and l.inserted_at == f.inserted_at,
      where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.scope_kind in @scopes,
      select: %{
        scope_kind: f.scope_kind,
        scope_id: f.scope_id,
        path: f.path
      }
    )
  end

  defp rows(scope, paths, base) do
    kind = value(scope, :kind, "")
    module_name = value(scope, :module, "")
    suite_name = value(scope, :suite, "")
    name = value(scope, :name, "")

    with true <- kind in @scopes and module_name != "",
         scope_id when is_binary(scope_id) <- scope_id(kind, module_name, suite_name, name) do
      scope
      |> value(:files, [])
      |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 < tuple_size(paths)))
      |> Enum.uniq()
      |> Enum.map(fn index ->
        Map.merge(base, %{
          id: UUIDv7.generate(),
          scope_kind: kind,
          scope_id: scope_id,
          path: elem(paths, index)
        })
      end)
    else
      _ -> []
    end
  end

  defp scope_id("test", _module_name, _suite_name, ""), do: nil
  defp scope_id("test", module_name, suite_name, name), do: test_scope_id(module_name, suite_name, name)
  defp scope_id("suite", _module_name, "", _name), do: nil
  defp scope_id("suite", module_name, suite_name, _name), do: suite_scope_id(module_name, suite_name)
  defp scope_id("target", module_name, _suite_name, _name), do: module_name

  defp value(map, key, default) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key)) || default
      found -> found
    end
  end
end
