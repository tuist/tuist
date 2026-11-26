defmodule Tuist.Tests.Coverage.Evidence do
  @moduledoc """
  Which files each test of a run executed: the evidence test selection plans
  over (a test is a candidate when a file it covered changed) and what says
  how much of a suite has evidence at all.

  The client's coverage observer records the coverage counters each test
  moved and reduces them to source files; the run reports them as
  `coverage_evidence` (`paths` once, and scopes referring to them by index).
  They are stored in `coverage_files`, apart from the run's own coverage
  (`coverage_run_files`), told apart by the scope:

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
  the commit's listing. No reader of coverage reads them, so these rows
  never reach a total. Like the run's coverage, a report replaces the shard's
  earlier one: readers use each shard's latest.

  The rows are only what a commit's fold builds its test maps from
  (`Tuist.TestImpactAnalysis.Snapshots`), seconds after the run reports, so
  they expire `retention_days/0` after they were inserted, long before the
  run's own rows.
  """
  alias Tuist.ClickHouse.Inserts
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.CoverageFile
  alias TuistCommon.Ingestion.Bufferable

  require Logger

  # Joins a scope id's parts. A unit separator, because a slash would not
  # survive a Bazel label (`//app/core:tests`) or a test name that holds one.
  @separator "\x1F"
  @insert_chunk_size 5_000
  @scopes ~w(test suite target)
  # The lines a report's ranges may expand to, over all its scopes and files.
  # Ranges cost the client a few bytes whatever they span, so past this a
  # file's evidence keeps only that the scope ran it.
  @line_budget 10_000_000
  # An uploaded file is read inside the request that creates the run: at
  # most this much compressed (the signed URL takes any size, so an object
  # past it is refused before it is fetched), at most this much inflated, no
  # scope larger than the whole inline request may be, and no more paths or
  # scopes than the inline form accepts. Evidence compresses at least 4x even
  # with unrelated paths in every scope, so a file within the inflated limit
  # is within the compressed one.
  @upload_max_compressed_bytes 250_000_000
  @upload_max_inflated_bytes 1_000_000_000
  @upload_max_line_bytes 50_000_000
  @upload_max_paths 200_000
  @upload_max_scopes 500_000
  @retention_days 2

  @doc """
  How many days evidence rows are kept after they were inserted: the
  `coverage_files` time-to-live for every scope but `run`.
  """
  def retention_days, do: @retention_days

  @doc """
  Stores a run's evidence. `evidence` is the request's `coverage_evidence`,
  atom or string keyed; nil, or coverage turned off for the project, stores
  nothing. `:line_budget` caps the lines the report's ranges expand to; a file
  whose lines would exceed what is left keeps only its path.
  """
  def record(test, evidence, shard_index \\ nil, opts \\ [])
  def record(%{reporting_version: 1}, _evidence, _shard_index, _opts), do: :skipped
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

      # One insert, encoded a chunk at a time as the request streams it: the
      # rows share one `inserted_at`, so they land as one part and a reader
      # sees all of the report's evidence or none of it. Columns a row leaves
      # out take their type's default.
      %{fields: fields, encoding_types: types, header: header, insert_sql: sql, insert_opts: insert_opts} =
        Bufferable.compile_time_prepare(CoverageFile)

      encoded = :counters.new(1, [])

      body =
        scopes
        |> Stream.transform(Keyword.get(opts, :line_budget, @line_budget), &rows(&1, paths, base, &2))
        |> Stream.chunk_every(@insert_chunk_size)
        |> Stream.map(fn chunk ->
          :counters.add(encoded, 1, length(chunk))
          chunk |> Enum.map(fn row -> Enum.map(fields, &Map.get(row, &1)) end) |> Ch.RowBinary._encode_rows(types)
        end)

      IngestRepo.with_retry(fn -> IngestRepo.query!(sql, Stream.concat([header], body), insert_opts) end)

      # The run's coverage totals wait for these rows (`Workers.TotalsWorker`).
      if :counters.get(encoded, 1) > 0,
        do: Inserts.record("coverage_files", Coverage.report_key(test_run_id, shard_index), project_id, base.inserted_at)
    end

    :ok
  end

  @doc """
  Calls `fun` with the run's attributes, `coverage_evidence` read from object
  storage first when the client uploaded it (`storage_key`, see
  `Tuist.Tests.Coverage.evidence_storage_key/2`) rather than sending `paths`
  and `scopes` inline. The upload is DEFLATE-compressed NDJSON, one scope per
  line naming its files by path. It is downloaded to a temporary file and
  inflated as it is read, once for the paths and again as the scopes stream
  from it, file indices in place of paths, so `record/4` and `test_states/2`
  see the inline shape without the scopes ever sitting in memory, or on disk,
  whole. The file is removed once `fun` returns.

  An upload over #{div(@upload_max_compressed_bytes, 1_000_000)} MB is not
  downloaded, and the download stops there should the object have been
  replaced since its size was read, so a run costs the request no more disk
  than that. The file is held to the inline form's limits: an upload that
  inflates past #{div(@upload_max_inflated_bytes, 1_000_000)} MB, has a scope larger than
  #{div(@upload_max_line_bytes, 1_000_000)} MB, or names more paths or scopes
  than the inline form accepts isn't read.

  An upload that can't be downloaded or read leaves the run without
  evidence, its status `failed`: evidence enriches a run and never fails it.
  A network-trusted run, which stores no evidence, has nothing downloaded.
  """
  def with_uploaded(attrs, fun) do
    case Map.get(attrs, :coverage_evidence) do
      %{storage_key: key} = evidence when is_binary(key) ->
        if Map.get(attrs, :submission_auth) == "network_trusted" do
          fun.(Map.put(attrs, :coverage_evidence, Map.delete(evidence, :storage_key)))
        else
          read_uploaded(attrs, evidence, key, fun)
        end

      _ ->
        fun.(attrs)
    end
  end

  defp read_uploaded(attrs, evidence, key, fun) do
    compressed = Path.join(System.tmp_dir!(), "coverage_evidence_#{System.unique_integer([:positive])}.deflate")
    evidence = Map.delete(evidence, :storage_key)

    try do
      evidence =
        with %{account: account} <- Projects.get_project_by_id(Map.get(attrs, :project_id)),
             :ok <- download(key, compressed, account),
             {:ok, paths} <- uploaded_paths(compressed) do
          Map.merge(evidence, %{paths: paths, scopes: uploaded_scopes(compressed, paths)})
        else
          problem ->
            Logger.warning(
              "The coverage evidence uploaded for test run #{Map.get(attrs, :id)} could not be read: #{inspect(problem)}"
            )

            Map.merge(evidence, %{paths: [], scopes: [], status: "failed"})
        end

      fun.(Map.put(attrs, :coverage_evidence, evidence))
    after
      File.rm(compressed)
    end
  end

  # Sized first, so an object past the limit is never fetched, then fetched
  # no further than the limit, in case it was replaced since: the signed URL
  # stays valid for an hour.
  defp download(key, destination, account) do
    with {:ok, size} <- Storage.get_object_size(key, account),
         :ok <- if(size > @upload_max_compressed_bytes, do: {:error, {:upload_too_large, size}}, else: :ok) do
      stream = Storage.stream_object(key, account)

      case File.open!(
             destination,
             [:write, :binary],
             &Enum.reduce_while(stream, {&1, 0}, fn chunk, acc -> write_chunk(chunk, acc) end)
           ) do
        {:error, reason} -> {:error, reason}
        _written -> :ok
      end
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp write_chunk(chunk, {file, size}) do
    size = size + byte_size(chunk)

    if size > @upload_max_compressed_bytes do
      {:halt, {:error, :upload_too_large}}
    else
      IO.binwrite(file, chunk)
      {:cont, {file, size}}
    end
  end

  # Every path the scopes name, once, in the order they first appear; an
  # error when a line isn't a JSON object or the file is past the limits.
  defp uploaded_paths(path) do
    path
    |> uploaded_lines()
    |> Enum.reduce_while({%{}, [], 0}, fn
      {:error, reason}, _acc ->
        {:halt, {:error, reason}}

      _line, {_seen, _paths, @upload_max_scopes} ->
        {:halt, {:error, :too_many_scopes}}

      line, {seen, paths, count} ->
        with {:ok, %{} = scope} <- JSON.decode(line),
             {seen, paths} <- scope_paths(scope, seen, paths) do
          {:cont, {seen, paths, count + 1}}
        else
          {:error, :too_many_paths} -> {:halt, {:error, :too_many_paths}}
          _ -> {:halt, {:error, :invalid_coverage_evidence}}
        end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {_seen, paths, _count} -> {:ok, Enum.reverse(paths)}
    end
  end

  defp scope_paths(scope, seen, paths) do
    scope
    |> Map.get("files")
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.reduce_while({seen, paths}, fn file, {seen, paths} ->
      cond do
        Map.has_key?(seen, file) -> {:cont, {seen, paths}}
        map_size(seen) == @upload_max_paths -> {:halt, {:error, :too_many_paths}}
        true -> {:cont, {Map.put(seen, file, true), [file | paths]}}
      end
    end)
  end

  # The scopes as the inline form holds them, read again on each pass.
  defp uploaded_scopes(path, paths) do
    index = paths |> Enum.with_index() |> Map.new()

    path
    |> uploaded_lines()
    |> Stream.map(fn line ->
      scope = JSON.decode!(line)
      Map.put(scope, "files", scope |> Map.get("files") |> List.wrap() |> Enum.map(&Map.get(index, &1, -1)))
    end)
  end

  # The upload's non-empty lines, inflated a chunk at a time on each pass
  # rather than to disk. `{:error, reason}` ends the stream when the upload
  # isn't whole DEFLATE, inflates past `@upload_max_inflated_bytes`, or has a
  # line past `@upload_max_line_bytes`, which is never held as one binary.
  defp uploaded_lines(path) do
    path
    |> inflated_chunks()
    |> Stream.transform(fn -> {[], 0} end, &split_lines/2, &last_line/1, fn _acc -> :ok end)
    |> Stream.reject(&(&1 == ""))
  end

  defp inflated_chunks(path) do
    Stream.resource(
      fn ->
        z = :zlib.open()
        :ok = :zlib.inflateInit(z, -15)
        %{z: z, file: File.open!(path, [:read, :binary]), size: 0, continue: false, done: false}
      end,
      &next_inflated/1,
      fn %{z: z, file: file} ->
        File.close(file)
        :zlib.close(z)
      end
    )
  end

  defp next_inflated(%{done: true} = state), do: {:halt, state}

  # One `safeInflate` output at a time, so that a chunk inflating to far more
  # than itself is never in memory whole.
  defp next_inflated(%{z: z} = state) do
    case inflate_step(state) do
      :eof ->
        # `inflateEnd` is what fails on a stream that was cut off.
        :zlib.inflateEnd(z)
        {:halt, state}

      {status, output} ->
        output = IO.iodata_to_binary(output)
        size = state.size + byte_size(output)

        if size > @upload_max_inflated_bytes,
          do: {[{:error, :inflates_too_large}], %{state | done: true}},
          else: {[output], %{state | size: size, continue: status == :continue}}
    end
  rescue
    ErlangError -> {[{:error, :invalid_deflate}], %{state | done: true}}
  end

  defp inflate_step(%{continue: true, z: z}), do: :zlib.safeInflate(z, [])

  defp inflate_step(%{z: z, file: file}) do
    case IO.binread(file, 65_536) do
      data when is_binary(data) -> :zlib.safeInflate(z, data)
      _eof -> :eof
    end
  end

  defp split_lines(_chunk, :ended), do: {:halt, :ended}
  defp split_lines({:error, _reason} = error, _acc), do: {[error], :ended}

  defp split_lines(chunk, {parts, size}) do
    case :binary.split(chunk, "\n", [:global]) do
      [partial] ->
        pending(parts, size, partial, [])

      [first | rest] ->
        {complete, [partial]} = Enum.split(rest, -1)

        if size + byte_size(first) > @upload_max_line_bytes,
          do: {[{:error, :scope_too_large}], :ended},
          else: pending([], 0, partial, [IO.iodata_to_binary(Enum.reverse([first | parts])) | complete])
    end
  end

  defp pending(parts, size, partial, lines) do
    if size + byte_size(partial) > @upload_max_line_bytes,
      do: {lines ++ [{:error, :scope_too_large}], :ended},
      else: {lines, {[partial | parts], size + byte_size(partial)}}
  end

  defp last_line(:ended), do: {[], :ended}
  defp last_line({parts, _size}), do: {[IO.iodata_to_binary(Enum.reverse(parts))], {[], 0}}

  @doc """
  The tests a report holds evidence of their own for, as `{name,
  module_name, suite_name}`: what marks their test case runs
  (`coverage_evidence` `own` on `test_case_runs`), so a test's latest evidence
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

  @doc """
  What a report's evidence holds for each test it names, by `{name,
  module_name, suite_name}`, as their test case runs record it
  (`coverage_evidence`): `own` for the tests it holds evidence of their own
  for (`tests_with_evidence/2`), `overlapped` for those it recorded only as
  overlapping another test of their process (`overlapped_tests/2`). Tests it
  doesn't name are `none`.
  """
  def test_states(project_id, evidence) do
    overlapped = project_id |> overlapped_tests(evidence) |> Map.new(&{&1, "overlapped"})
    own = project_id |> tests_with_evidence(evidence) |> Map.new(&{&1, "own"})
    Map.merge(overlapped, own)
  end

  @doc """
  The tests the report recorded only as overlapping another test of their
  process (Swift Testing running in parallel), so nothing could be attributed
  to them, as `{name, module_name, suite_name}`. Empty when coverage is off
  for the project.
  """
  def overlapped_tests(_project_id, nil), do: MapSet.new()

  def overlapped_tests(project_id, evidence) do
    tests = value(evidence, :overlapped_tests, []) || []

    if is_list(tests) and tests != [] and Coverage.enabled_for_project?(project_id) do
      tests
      |> Enum.filter(&is_map/1)
      |> Enum.map(&{value(&1, :name, ""), value(&1, :module, ""), value(&1, :suite, "") || ""})
      |> Enum.reject(fn {name, module_name, _suite} -> name in [nil, ""] or module_name in [nil, ""] end)
      |> MapSet.new()
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

  @doc "The line numbers of `line_ranges/1`'s runs, ascending."
  def range_lines(ranges), do: Enum.flat_map(ranges, fn [first, last] -> first..last//1 end)

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

  # Strongest first: a run collected evidence when any of its shards did.
  @statuses ~w(collected failed not_linked)

  @doc """
  Whether the run collected evidence, from the request's `coverage_evidence`:
  `collected`, `not_linked` (asked for, but no test process recorded any: no
  target links TestCoverageAttribution), `failed`, or `""` when the run didn't
  ask for any.
  """
  def status(nil), do: ""

  def status(evidence) do
    status = evidence |> value(:status, "") |> to_string()
    if status in @statuses, do: status, else: ""
  end

  @doc "A sharded run's status from two of its shards': the strongest of the two."
  def merge_status(current, incoming) do
    Enum.find(@statuses, "", &(&1 in [current, incoming]))
  end

  defp value(map, key, default) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key)) || default
      found -> found
    end
  end
end
