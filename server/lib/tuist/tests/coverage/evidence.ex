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

  - `test`: what one test executed, `scope_id` the module, the suite (empty
    for a test outside any) and the name: the fields a test case's stable id
    is made of (`Tuist.Tests.generate_test_case_id/4`), joined by a unit
    separator so that any of them may hold a slash;
  - `suite`: what ran around a suite's tests and belongs to none (class
    `setUp`, a one-time bootstrap), `scope_id` the module and the suite; every
    test of the suite may depend on it;
  - `target`: everything the target's processes executed, `scope_id` the
    module: the floor for each of its tests, and all there is for the tests
    nothing could be attributed to (Swift Testing running in parallel).

  Evidence rows hold a path and, when the client could tell them, the lines
  the scope ran in it (`line_numbers`, with `covered_lines` their count; an
  empty list means only the file is known). They hold no execution counts and
  no blob, which is read off the run's own row for the path or
  the commit's listing. Every reader of coverage filters on the `run` scope, so these rows
  never reach a total. Like the run's coverage, a report replaces the shard's
  earlier one: readers use each shard's latest.
  """
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.CoverageFile

  # Joins a scope id's parts. A unit separator, because a slash would not
  # survive a Bazel label (`//app/core:tests`) or a test name that holds one.
  @separator "\x1F"
  @insert_chunk_size 5_000
  @scopes ~w(test suite target)
  # The lines a report's ranges may expand to, over all its scopes and files.
  # Ranges cost the client a few bytes whatever they span, so past this a
  # file's evidence keeps only that the scope ran it.
  @line_budget 10_000_000

  @doc """
  Stores a run's evidence. `evidence` is the request's `coverage_evidence`,
  atom or string keyed; nil, or coverage turned off for the project, stores
  nothing. `:line_budget` caps the lines the report's ranges expand to; a file
  whose lines would exceed what is left keeps only its path.
  """
  def record(test, evidence, shard_index \\ nil, opts \\ [])
  def record(_test, nil, _shard_index, _opts), do: :ok

  def record(%{id: test_run_id, project_id: project_id} = test, evidence, shard_index, opts) do
    paths = evidence |> value(:paths, []) |> List.to_tuple()
    scopes = value(evidence, :scopes, [])

    if Coverage.enabled_for_project?(project_id) and tuple_size(paths) > 0 and scopes != [] do
      base = %{
        test_run_id: test_run_id,
        project_id: project_id,
        build_system: to_string(Map.get(test, :build_system) || "xcode"),
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
      |> Stream.transform(Keyword.get(opts, :line_budget, @line_budget), &rows(&1, paths, base, &2))
      |> Stream.chunk_every(@insert_chunk_size)
      |> Enum.each(&IngestRepo.insert_all(CoverageFile, &1))
    end

    :ok
  end

  @doc """
  The tests a report holds evidence of their own for, as `{name,
  module_name, suite_name}`: what marks their test case runs
  (`has_coverage_evidence` on `test_case_runs`), so a test's latest evidence
  is found through its runs rather than by scanning `coverage_files`. Empty
  when coverage is off for the project, as `record/3` then stores nothing.
  """
  def tests_with_evidence(_project_id, nil), do: MapSet.new()

  def tests_with_evidence(project_id, evidence) do
    scopes = value(evidence, :scopes, [])

    if scopes != [] and Coverage.enabled_for_project?(project_id) do
      paths_count = evidence |> value(:paths, []) |> length()
      scopes |> Enum.map(&evidence_identity(&1, paths_count)) |> Enum.reject(&is_nil/1) |> MapSet.new()
    else
      MapSet.new()
    end
  end

  # A test scope's `{name, module_name, suite_name}`, as a test case run is
  # keyed, when `record/3` stores rows for it: at least one of its files
  # points at a reported path.
  defp evidence_identity(scope, paths_count) do
    name = value(scope, :name, "")
    module_name = value(scope, :module, "")

    if value(scope, :kind, "") == "test" and name != "" and module_name != "" and
         scope |> value(:files, []) |> Enum.any?(&valid_file_index?(&1, paths_count)),
       do: {name, module_name, value(scope, :suite, "") || ""}
  end

  defp valid_file_index?(index, paths_count), do: is_integer(index) and index >= 0 and index < paths_count

  @doc false
  def test_scope_id(module_name, suite_name, name), do: Enum.join([module_name, suite_name, name], @separator)

  @doc false
  def suite_scope_id(module_name, suite_name), do: Enum.join([module_name, suite_name], @separator)

  @doc "Line numbers as `[first, last]` runs of consecutive lines, ascending."
  def line_ranges(line_numbers) do
    line_numbers
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce([], fn
      line, [[first, last] | rest] when line == last + 1 -> [[first, line] | rest]
      line, ranges -> [[line, line] | ranges]
    end)
    |> Enum.reverse()
  end

  defp rows(scope, paths, base, budget) do
    kind = value(scope, :kind, "")
    module_name = value(scope, :module, "")
    suite_name = value(scope, :suite, "")
    name = value(scope, :name, "")

    with true <- kind in @scopes and module_name != "",
         scope_id when is_binary(scope_id) <- scope_id(kind, module_name, suite_name, name) do
      files = value(scope, :files, [])
      lines = value(scope, :lines, nil) || []

      files
      |> Enum.zip(Stream.concat(lines, Stream.repeatedly(fn -> [] end)))
      |> Enum.filter(fn {index, _ranges} -> valid_file_index?(index, tuple_size(paths)) end)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map_reduce(budget, fn {index, ranges}, budget ->
        {line_numbers, budget} = line_numbers(ranges, budget)

        row =
          Map.merge(base, %{
            id: UUIDv7.generate(),
            scope_kind: kind,
            scope_id: scope_id,
            path: elem(paths, index),
            line_numbers: line_numbers,
            covered_lines: length(line_numbers)
          })

        {row, budget}
      end)
    else
      _ -> {[], budget}
    end
  end

  # Inclusive ranges flattened: `[3, 5, 9, 9]` is lines 3 to 5 and line 9.
  # Overlapping ranges are merged before anything is expanded, so repeating a
  # range adds nothing.
  defp line_numbers(ranges, budget) when is_list(ranges) do
    merged =
      ranges
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.filter(fn [first, last] ->
        is_integer(first) and is_integer(last) and first > 0 and last >= first and last - first < 100_000
      end)
      |> Enum.sort()
      |> Enum.reduce([], fn
        [first, last], [[merged_first, merged_last] | rest] when first <= merged_last + 1 ->
          [[merged_first, max(last, merged_last)] | rest]

        range, merged ->
          [range | merged]
      end)
      |> Enum.reverse()

    count = Enum.sum_by(merged, fn [first, last] -> last - first + 1 end)

    if count <= budget do
      {Enum.flat_map(merged, fn [first, last] -> Enum.to_list(first..last) end), budget - count}
    else
      {[], budget}
    end
  end

  defp line_numbers(_ranges, budget), do: {[], budget}

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
