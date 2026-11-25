defmodule Tuist.Tests.Coverage do
  @moduledoc """
  Code coverage for test runs, in a model shared by every build system.

  Xcode coverage is measured on the client: `llvm-cov export` over the test
  products with the run's merged profile, which reports code `xccov` leaves
  out (the binary cache's, and sources compiled with a coverage prefix map),
  with `xccov view --report` only for which target compiled each file. It
  arrives as the `coverage` block with `tool` `llvm-cov`, whichever processing
  mode the run used. Older clients, and runs the client could not export, keep
  the previous path: the shared Swift parser reads the bundle (`xccov view
  --report` for targets and functions, `xccov view --archive` for per-line
  execution counts) wherever the bundle is processed, on the server's macOS
  processors for uploaded bundles (unless the bundle's manifest says the
  client reported the coverage), or on the client in local mode. The client
  ties the files to the repository with the Git blob each had, which only the
  checkout knows. Mix coverage is
  read by `tuist_ex` from Erlang's `cover` once the suite finished, and arrives
  in the same per-file shape: an OTP application is a target, and the files
  under the project's test paths are test code. JaCoCo (Gradle)
  and LCOV (Bazel) reports map onto the same rows: a module or label is a
  target, a method is a function, and their branch counters fill the columns
  `xccov` leaves empty.

  Every file a report covered is stored in `coverage_run_files` with its
  counts, tagged with the build system, and the file's version (blob,
  executable lines, functions) once per week in `coverage_file_layouts`,
  which the rows name: runs of the same version would otherwise repeat it in
  every row. `report_files_for_runs/2` joins them back. The per-test evidence
  is stored apart, in `coverage_files` (`Tuist.Tests.Coverage.Evidence`).
  `in_repository` marks the paths Git knows, the only ones evidence may rely
  on. Test code (files only `.xctest` bundles compiled) is stored but left
  out of every figure: a test that runs covers its own body, which says nothing
  about the product. A run that left tests out on purpose (selective testing,
  `-only-testing`) is marked partial: its coverage describes the tests that ran
  and nothing else, so it stays out of the coverage trend.

  A sharded run gets a report per shard. A report's rows share `inserted_at`
  and only each shard's latest report is read, so a retried or reprocessed
  shard replaces what it sent before. Readers merge the reports of a path: the
  executable and covered lines are the union across shards, since shards run
  disjoint tests over the same sources.

  Shards report concurrently, so no report can safely rewrite totals another
  one computed. The run page derives the totals from the reports, and the
  coverage trend reads `coverage_runs`, where every report publishes the
  totals over the shards reported so far and the most complete computation
  wins, whatever order the reports land in. The totals carry the run's scheme
  and the tool and version that measured them, and the repository's Git
  object format, so figures are only ever compared like with like.

  Excluded paths (generated code, see `Tuist.Tests.Coverage.ExcludedPaths`)
  are stored like any other but left out of every figure: the published
  totals, and the files, targets and totals read from the reports.
  """

  import Ecto.Query

  alias Tuist.ClickHouse.ArrayInParams
  alias Tuist.ClickHouse.Inserts
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.RunInputs
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.Coverage.Workers.TotalsWorker
  alias Tuist.Tests.CoverageFileLayout
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.CoverageRunFile
  alias Tuist.Tests.Test
  alias Tuist.Tests.Workers.PublishCoverageWorker
  alias TuistCommon.Ingestion.Bufferable

  @insert_chunk_size 2_000
  @max_count 4_294_967_295

  # The build systems whose clients report coverage (`supported?/1`). Add one
  # here once its client does.
  @build_systems [:xcode, :mix, :cargo, :gradle, :once]

  # ClickHouse sends every query parameter as an HTTP form field and refuses a
  # request carrying more than `http_max_fields`, which defaults to 1000. A
  # query that binds a list therefore has to be split, and each chunk has to
  # leave room for whatever else the query binds — above all a second list,
  # like the run ids a per-test lookup is scoped to. The budget is kept under
  # the default so an install that never touched the setting still works.
  # A list bound with `in ^list` travels as one array field, which ClickHouse
  # also refuses past `http_max_field_value_size` (128 KiB, URL-encoded), so a
  # list of paths needs chunking as much as a list of ids does.
  @max_query_parameters 900

  @doc """
  Records the targets a run's command event stored (`stored_graph`, from
  `Tuist.Xcode.create_xcode_graph/1`) as an input of the fold of the run's
  commit (`Tuist.Tests.Coverage.RunInputs`), and refolds the commit when any
  target was skipped or a repository target came from the binary cache.
  Reported coverage reads them to know which targets a run left out and
  whether it ran code without coverage counters. The event usually lands
  after the run, whose fold went without them; the refold waits until every
  replica holds them. The commit is the event's, which names the same
  checkout as its run.
  """
  def refold_after_selective_testing(command_event, xcode_graph, stored_graph) do
    RunInputs.event_written(command_event, stored_graph)

    with %{test_run_id: run_id, git_commit_sha: sha, project_id: project_id}
         when is_binary(run_id) and run_id != "" and is_binary(sha) and sha != "" <- command_event,
         true <- selective_testing_hit?(xcode_graph) or binary_cache_hit?(xcode_graph),
         true <- enabled_for_project?(project_id) do
      CommitWorker.enqueue(project_id, sha)
    else
      _ -> :skipped
    end
  end

  defp selective_testing_hit?(xcode_graph) do
    xcode_graph
    |> field(:projects, [])
    |> Enum.flat_map(&field(&1, :targets, []))
    |> Enum.any?(fn target ->
      target
      |> field(:selective_testing_metadata, %{})
      |> field(:hit, "miss")
      |> to_string()
      |> Kernel.in(["local", "remote"])
    end)
  end

  # A remote package's targets carry its revision as their external hash, and
  # `Coverage.Xcode.uninstrumented_targets/2` leaves them out.
  defp binary_cache_hit?(xcode_graph) do
    xcode_graph
    |> field(:projects, [])
    |> Enum.flat_map(&field(&1, :targets, []))
    |> Enum.any?(fn target ->
      metadata = field(target, :binary_cache_metadata, %{})

      to_string(field(metadata, :hit, "miss")) in ["local", "remote"] and
        field(field(metadata, :subhashes, %{}), :external, "") == ""
    end)
  end

  defp field(nil, _key, default), do: default
  defp field(map, key, default), do: Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default

  @doc false
  def id_chunks(ids, reserved \\ 0), do: Enum.chunk_every(ids, max(@max_query_parameters - reserved, 1))

  # A published version ranks the shards a computation included above the
  # newest report it saw, in microseconds, which stay below 2^51 until 2041.
  @shard_count_weight 2 ** 51

  @doc """
  A run's attributes with the coverage it reported under `coverage`, whichever
  form the client sent it in: the build-system-neutral `coverage` block, or the
  `xcode_coverage` block (and `xcode_coverage_storage_key` with
  `xcode_coverage_partial` for an uploaded one), measured by `xccov` with the
  run's Xcode.
  """
  def normalize_attrs(attrs) do
    {xcode_coverage, attrs} = Map.pop(attrs, :xcode_coverage)
    {storage_key, attrs} = Map.pop(attrs, :xcode_coverage_storage_key)
    {partial, attrs} = Map.pop(attrs, :xcode_coverage_partial)
    xccov = %{tool: "xccov", tool_version: Map.get(attrs, :xcode_version) || ""}

    cond do
      not is_nil(Map.get(attrs, :coverage)) ->
        Map.update!(attrs, :coverage, &plain/1)

      not is_nil(xcode_coverage) ->
        Map.put(attrs, :coverage, Map.merge(plain(xcode_coverage), xccov))

      not is_nil(storage_key) ->
        Map.put(attrs, :coverage, Map.merge(xccov, %{storage_key: storage_key, partial: partial}))

      true ->
        attrs
    end
  end

  defp plain(%_{} = struct), do: Map.from_struct(struct)
  defp plain(map), do: map

  @doc """
  The rows to store for the `coverage` block reported with a run, or nil when
  the project's account does not have coverage enabled. Only files the client
  found in Git, under a repository-relative path, are evidence.

  The block either carries its `files` inline, or a `path` to the file the
  parser streamed them to (one JSON object per line), which comes back as a
  lazy stream so a large report is never held whole. A block whose files were
  uploaded instead (`storage_key`) has no rows yet: `enqueue_publish/4` reads
  them back. String and atom keys are both accepted: the inline form arrives
  cast by the API, the streamed form decoded from JSON.
  """
  def rows(_project_id, nil), do: nil

  def rows(project_id, coverage) do
    if is_nil(value(coverage, :storage_key, nil)) and enabled_for_project?(project_id), do: rows(coverage)
  end

  @doc """
  Whether the project's build system reports code coverage, so Tuist ingests,
  serves and shows it: Xcode, Mix, Cargo and Gradle projects, in every account. The
  ingestion, the API, the MCP tools, the pages and the sidebar all follow it.
  """
  def supported?(%Project{build_system: build_system}), do: build_system in @build_systems

  @doc false
  def enabled_for_project?(project_id) do
    case Projects.get_project_by_id(project_id) do
      nil -> false
      project -> supported?(project)
    end
  end

  defp rows(coverage) do
    files =
      case value(coverage, :path, nil) do
        nil ->
          coverage |> value(:files, []) |> Enum.map(&file_row/1)

        path ->
          path
          |> File.stream!()
          |> Stream.map(&String.trim_trailing(&1, "\n"))
          |> Stream.reject(&(&1 == ""))
          |> Stream.map(&(&1 |> JSON.decode!() |> file_row()))
      end

    %{
      partial: value(coverage, :partial, false),
      tool: value(coverage, :tool, ""),
      tool_version: value(coverage, :tool_version, ""),
      platform: value(coverage, :platform, ""),
      files: files
    }
  end

  @doc """
  Stores one report's files and publishes the run's totals over every shard
  reported so far. `shard_index` is nil for an unsharded run, and
  `expected_shards` is how many shards the run's plan has: until each of them
  reported coverage, the published totals are partial, since the missing
  shards' tests are not in them.

  The totals reach `coverage_runs` only once every replica holds the
  report's rows (`Workers.TotalsWorker`): at once when they already do,
  otherwise moments later from a job, which then folds the commit again.

  It does not fold the run's commit: the caller schedules that with
  `enqueue_fold/2` once it has written the rest of the run.
  """
  def publish(test, coverage, shard_index, expected_shards \\ 1)

  def publish(%Test{reporting_version: 1}, _coverage, _shard_index, _expected_shards), do: :skipped

  def publish(%Test{}, nil, _shard_index, _expected_shards), do: :ok

  def publish(%Test{} = test, coverage, shard_index, expected_shards) do
    shard_index = shard_index || 0
    reported_at = NaiveDateTime.utc_now()

    :telemetry.span(Tuist.Telemetry.event_name_coverage_publish(), %{project_id: test.project_id}, fn ->
      excluded = ExcludedPaths.pattern_for_project(test.project_id)
      others = other_shards(test.project_id, test.id, shard_index, excluded)
      excluded_regex = ExcludedPaths.compile(excluded)
      folded = insert_files_and_fold(test, coverage, shard_index, reported_at, others, excluded_regex)
      :ok = Inserts.record("coverage_run_files", report_key(test.id, shard_index), test.project_id, reported_at)
      run = totals_row(test, coverage, {shard_index, expected_shards}, reported_at, others, folded)
      :ok = TotalsWorker.publish(run, shard_index, reported_at, folded.files)

      {:ok, %{files: folded.files, covered_lines: elem(folded.totals, 0), executable_lines: elem(folded.totals, 1)}}
    end)
  end

  @doc """
  Schedules the fold of the run's commit (`Commits.enqueue_recompute/1`).
  Call it only after everything the run reports is written, test case runs
  included: the fold reads them, and nothing folds the commit again when they
  land after it. `coverage` is the run's `coverage` block, or nil.

  A run that measured nothing still changes what its commit knows: a scheme
  selective testing skipped whole reports no coverage, and the commit's
  reported figure carries that scheme's tests forward only once it can see
  the run. It can land after the completion signal, so the commit is
  refolded then too, but only when it is already measured, so a project that
  never reports coverage schedules nothing.
  """
  def enqueue_fold(%Test{reporting_version: 1}, _coverage), do: :skipped
  def enqueue_fold(%Test{submission_auth: "network_trusted"}, _coverage), do: :skipped

  def enqueue_fold(%Test{} = test, coverage) do
    if (not is_nil(coverage) and enabled_for_project?(test.project_id)) or
         Commits.measured?(test.project_id, test.git_commit_sha),
       do: Commits.enqueue_recompute(test),
       else: :skipped
  end

  @doc """
  Where a client that processed the bundle itself uploads a run's coverage
  (see `TuistWeb.API.CoverageController`): under the run, so it lives as long
  as the run's other artifacts.
  """
  def storage_key(%{account: %{name: account}, name: project}, test_run_id) do
    "#{account}/#{project}/runs/#{test_run_id}/coverage.ndjson.deflate"
  end

  @doc """
  Where a client uploads a run's per-test coverage evidence when it doesn't
  send it inline (`Tuist.Tests.Coverage.Evidence.with_uploaded/2`), beside
  the run's coverage.
  """
  def evidence_storage_key(%{account: %{name: account}, name: project}, test_run_id) do
    "#{account}/#{project}/runs/#{test_run_id}/coverage_evidence.ndjson.deflate"
  end

  @doc """
  Schedules the publication of coverage a client uploaded for the run, once
  the run exists. `coverage` is the run's block, naming the upload's
  `storage_key`, the tool that measured it, and whether the run was `partial`;
  the shard arguments are those of `publish/4`.
  """
  def enqueue_publish(%Test{reporting_version: 1}, _coverage, _shard_index, _expected_shards), do: :skipped

  def enqueue_publish(%Test{} = test, coverage, shard_index, expected_shards) do
    if enabled_for_project?(test.project_id) do
      %{
        test_run_id: test.id,
        project_id: test.project_id,
        account_id: test.account_id,
        storage_key: value(coverage, :storage_key, nil),
        partial: value(coverage, :partial, false) || false,
        tool: value(coverage, :tool, ""),
        tool_version: value(coverage, :tool_version, ""),
        platform: value(coverage, :platform, ""),
        shard_index: shard_index,
        expected_shards: expected_shards
      }
      |> PublishCoverageWorker.new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  # One pass over the report's files, which may be a lazy stream: each chunk's
  # layouts are inserted and its files folded into the run's totals as it goes
  # by, so nothing holds the report whole. The report's own files are merged
  # from memory, since rows inserted moments ago are not reliably read back
  # within the same request; the other shards' latest reports come from
  # ClickHouse. A file's lines are only kept when another shard reported the
  # same path, for the union; every other file adds its counts and is let go.
  # Excluded paths are stored and counted as files, but add nothing to the
  # totals.
  #
  # The run's rows are encoded to a scratch file as the chunks go by and sent
  # afterwards as one insert. They share one `inserted_at`, so they land as
  # one part, which every replica attaches whole: a reader sees all of the
  # report or none of it, never the chunks inserted so far. Each chunk's
  # layouts were acknowledged before that insert starts.
  defp insert_files_and_fold(
         %Test{id: test_run_id, project_id: project_id} = test,
         coverage,
         shard_index,
         reported_at,
         others,
         excluded
       ) do
    others_by_path = Map.new(others.files)

    report = %{
      test_run_id: test_run_id,
      project_id: project_id,
      build_system: test.build_system,
      shard_index: shard_index,
      partial: coverage.partial,
      git_commit_sha: test.git_commit_sha || "",
      reported_on: NaiveDateTime.to_date(reported_at),
      inserted_at: reported_at
    }

    {{covered, executable}, overlap, object_format, files} =
      with_scratch_file(fn path ->
        folded =
          File.open!(path, [:write, :binary], fn io ->
            coverage.files
            |> Stream.chunk_every(@insert_chunk_size)
            |> Enum.reduce({{0, 0}, %{}, "", 0}, fn chunk, acc ->
              IO.binwrite(io, insert_report_layouts(report, chunk))

              Enum.reduce(chunk, acc, &fold_file(&1, &2, others_by_path, excluded))
            end)
          end)

        if elem(folded, 3) > 0, do: insert_encoded_file(CoverageRunFile, path)
        folded
      end)

    totals =
      Enum.reduce(others_by_path, {covered, executable}, fn {path, evidence}, {covered, executable} ->
        {path_covered, path_executable} =
          case Map.fetch(overlap, path) do
            {:ok, own_evidence} -> merge_evidence([own_evidence, evidence])
            :error -> merge_evidence([evidence])
          end

        {covered + path_covered, executable + path_executable}
      end)

    %{totals: totals, object_format: object_format, files: files}
  end

  defp fold_file(file, {totals, overlap, object_format, files}, others_by_path, excluded) do
    object_format = if object_format == "", do: git_object_format(file), else: object_format

    cond do
      file.is_test or ExcludedPaths.excluded?(excluded, file.path) ->
        {totals, overlap, object_format, files + 1}

      Map.has_key?(others_by_path, file.path) ->
        {totals, Map.put(overlap, file.path, file_evidence(file)), object_format, files + 1}

      true ->
        {covered, executable} = totals
        {{covered + file.covered_lines, executable + file.executable_lines}, overlap, object_format, files + 1}
    end
  end

  # A chunk of a report's files: inserts their versions the week doesn't hold
  # yet and returns the run's rows naming them, encoded for the report's one
  # insert. Shards reporting at once may both write a version; readers take
  # either copy. Known versions are looked up within the chunk's range of
  # paths, which the layouts' sort key starts with after the week, so reports
  # listing files in path order read only theirs.
  defp insert_report_layouts(report, files) do
    files =
      Enum.map(files, &Map.merge(&1, %{layout_id: layout_id(&1), epoch: layout_epoch(&1.path, report.reported_on)}))

    layouts = Enum.uniq_by(files, &{&1.path, &1.layout_id})
    {first_path, last_path} = layouts |> Enum.map(& &1.path) |> Enum.min_max()

    known =
      from(l in CoverageFileLayout,
        where:
          l.project_id == ^report.project_id and l.epoch in ^(layouts |> Enum.map(& &1.epoch) |> Enum.uniq()) and
            l.path >= ^first_path and l.path <= ^last_path and
            l.layout_id in ^Enum.map(layouts, & &1.layout_id),
        select: {l.epoch, l.path, l.layout_id}
      )
      |> ClickHouseRepo.all()
      |> MapSet.new()

    new_layouts =
      for file <- layouts, not MapSet.member?(known, {file.epoch, file.path, file.layout_id}) do
        %{
          project_id: report.project_id,
          epoch: file.epoch,
          path: file.path,
          layout_id: file.layout_id,
          git_blob_id: file.git_blob_id,
          line_numbers: file.line_numbers,
          function_names: file.function_names,
          function_line_numbers: file.function_line_numbers,
          function_executable_lines: file.function_executable_lines
        }
      end

    if new_layouts != [], do: insert_encoded(CoverageFileLayout, new_layouts)

    encode_rows(CoverageRunFile, Enum.map(files, &run_file_row(report, &1)))
  end

  # A run row stores counts only when something ran, so a file the run
  # loaded but never executed costs no arrays.
  defp run_file_row(report, file) do
    functions_ran? =
      Enum.any?(file.function_execution_counts, &(&1 > 0)) or Enum.any?(file.function_covered_lines, &(&1 > 0))

    Map.merge(report, %{
      path: file.path,
      layout_id: file.layout_id,
      in_repository: file.in_repository,
      is_test: file.is_test,
      targets: file.targets,
      covered_lines: file.covered_lines,
      executable_lines: file.executable_lines,
      execution_counts: if(Enum.any?(file.execution_counts, &(&1 > 0)), do: capped(file.execution_counts), else: []),
      function_execution_counts: if(functions_ran?, do: capped(file.function_execution_counts), else: []),
      function_covered_lines: if(functions_ran?, do: file.function_covered_lines, else: [])
    })
  end

  # Run rows store counts as UInt32. No line has come near its maximum, but
  # RowBinary would wrap a larger count rather than reject it.
  defp capped(counts) do
    if Enum.any?(counts, &(&1 > @max_count)), do: Enum.map(counts, &min(&1, @max_count)), else: counts
  end

  # Encodes the rows to ClickHouse's RowBinary as the ingestion buffers do,
  # without Ecto dumping every value of every array first.
  defp insert_encoded(schema, rows) do
    %{header: header, insert_sql: sql, insert_opts: opts} = Bufferable.compile_time_prepare(schema)
    IngestRepo.query!(sql, [header, encode_rows(schema, rows)], opts)
  end

  defp encode_rows(schema, rows) do
    %{fields: fields, encoding_types: types} = Bufferable.compile_time_prepare(schema)

    rows
    |> Enum.map(fn row -> Enum.map(fields, &Map.fetch!(row, &1)) end)
    |> Ch.RowBinary._encode_rows(types)
    |> IO.iodata_to_binary()
  end

  # Sends the rows `encode_rows/2` wrote to the file as one insert, streamed
  # from disk in a chunked request. ClickHouse cuts an insert into parts only
  # past `max_insert_block_size` rows (about a million), far above any report.
  defp insert_encoded_file(schema, path) do
    %{header: header, insert_sql: sql, insert_opts: opts} = Bufferable.compile_time_prepare(schema)
    IngestRepo.query!(sql, Stream.concat([header], File.stream!(path, 1_048_576)), opts)
  end

  defp with_scratch_file(fun) do
    path = Path.join(System.tmp_dir!(), "tuist-coverage-#{UUIDv7.generate()}.rowbinary")

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  @doc """
  The first day of the week a file's layouts are stored under, for a report
  written on `date`. Each path starts its weeks on its own weekday (the CRC32
  of the path, modulo 7), so a project's versions are not all written again
  by the first report of the same day: each day's first report rewrites
  about a seventh of them. `RunFilesBackfillWorker` computes the same day in
  ClickHouse.
  """
  def layout_epoch(path, %Date{} = date) do
    days = Date.diff(date, ~D[1970-01-01])
    Date.add(date, -rem(days - rem(:erlang.crc32(path), 7), 7))
  end

  @doc """
  The id a file version's layout is stored under: a 32-bit hash of what the
  layout holds. It only has to tell apart one path's versions within a week
  (readers join on the path too), and a path has a handful of those, so 32
  bits keep collisions out of reach.
  """
  def layout_id(file) do
    layout =
      {file.path, file.git_blob_id, file.line_numbers, file.function_names, file.function_line_numbers,
       file.function_executable_lines}

    <<id::unsigned-32, _::binary>> = :crypto.hash(:sha256, :erlang.term_to_binary(layout, [:deterministic]))
    id
  end

  @doc """
  The key a shard report's inserts are recorded under in
  `Tuist.ClickHouse.Inserts`, which `Workers.TotalsWorker` waits for.
  """
  def report_key(test_run_id, shard_index), do: "#{test_run_id}/#{shard_index || 0}"

  # The report's `coverage_runs` row: totals over the shards reported so far,
  # versioned by how many those are, then by the newest report among them,
  # pinning the reports they cover: the others' newest, and this one when it
  # stored rows.
  defp totals_row(
         %Test{id: test_run_id, project_id: project_id} = test,
         coverage,
         {shard_index, expected_shards},
         reported_at,
         others,
         folded
       ) do
    {covered, executable} = folded.totals
    newest_report_at = Enum.max([reported_at, others.newest_report_at], NaiveDateTime)

    version =
      (others.shards_count + 1) * @shard_count_weight +
        NaiveDateTime.diff(newest_report_at, ~N[1970-01-01 00:00:00], :microsecond)

    pins = Enum.sort(if(folded.files > 0, do: [{shard_index, reported_at}], else: []) ++ others.reports)

    %{
      project_id: project_id,
      test_run_id: test_run_id,
      build_system: test.build_system,
      coverage_tool: coverage.tool,
      coverage_tool_version: coverage.tool_version,
      git_object_format: folded.object_format,
      scheme: test.scheme || "",
      platform: Map.get(coverage, :platform) || "",
      git_commit_sha: test.git_commit_sha || "",
      covered_lines: covered,
      executable_lines: executable,
      files: folded.files + others.files_count,
      partial: coverage.partial or others.partial or others.shards_count + 1 < expected_shards,
      version: version,
      inserted_at: NaiveDateTime.utc_now(),
      report_shards: Enum.map(pins, &elem(&1, 0)),
      report_inserted_at: Enum.map(pins, &elem(&1, 1))
    }
  end

  # A blob id is 40 hex digits in a SHA-1 repository and 64 in a SHA-256 one;
  # a file Git does not track says nothing about the repository.
  defp git_object_format(%{git_blob_id: <<_::binary-size(64)>>}), do: "sha256"
  defp git_object_format(%{git_blob_id: <<_::binary-size(40)>>}), do: "sha1"
  defp git_object_format(_file), do: ""

  defp other_shards(project_id, test_run_id, shard_index, excluded) do
    reports = from(f in report_files(project_id, test_run_id), where: f.shard_index != ^shard_index)

    files =
      from(f in without_excluded(reports, excluded),
        where: not f.is_test,
        group_by: f.path,
        select: {
          f.path,
          fragment("max(length(?))", f.line_numbers),
          max(f.covered_lines),
          max(f.executable_lines),
          fragment("groupUniqArrayArray(?)", f.line_numbers),
          fragment("groupUniqArrayArray(arrayFilter((l, c) -> c > 0, ?, ?))", f.line_numbers, f.execution_counts)
        }
      )
      |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
      |> Enum.map(fn
        {path, 0, covered, executable, _lines, _covered_lines} -> {path, {:counts, covered, executable}}
        {path, _, _, _, lines, covered_lines} -> {path, {:lines, MapSet.new(lines), MapSet.new(covered_lines)}}
      end)

    summary =
      ClickHouseRepo.one(
        from(f in report_files_for_runs(project_id, [test_run_id], lines: false, pinned: false),
          where: f.shard_index != ^shard_index,
          select: %{
            shards_count: fragment("uniqExact(?)", f.shard_index),
            files_count: count(),
            partial_rows: fragment("countIf(?)", f.partial),
            newest_report_at: max(f.inserted_at),
            reports: fragment("groupUniqArray((?, ?))", f.shard_index, f.inserted_at)
          }
        ),
        settings: [select_sequential_consistency: 1]
      )

    %{
      files: files,
      files_count: summary.files_count,
      shards_count: summary.shards_count,
      partial: summary.partial_rows > 0,
      newest_report_at: summary.newest_report_at || ~N[1970-01-01 00:00:00],
      reports: summary.reports || []
    }
  end

  defp file_evidence(%{line_numbers: [], covered_lines: covered, executable_lines: executable}),
    do: {:counts, covered, executable}

  defp file_evidence(file) do
    covered =
      file.line_numbers
      |> Enum.zip(file.execution_counts)
      |> Enum.flat_map(fn {line, count} -> if count > 0, do: [line], else: [] end)

    {:lines, MapSet.new(file.line_numbers), MapSet.new(covered)}
  end

  # As `merged_files_query/2`: the lines are the union across reports, and a
  # path no report has lines for keeps the largest counts.
  defp merge_evidence(evidence) do
    case for({:lines, lines, covered} <- evidence, do: {lines, covered}) do
      [] ->
        counts = for {:counts, covered, executable} <- evidence, do: {covered, executable}
        {counts |> Enum.map(&elem(&1, 0)) |> Enum.max(), counts |> Enum.map(&elem(&1, 1)) |> Enum.max()}

      line_sets ->
        {
          line_sets |> Enum.map(&elem(&1, 1)) |> Enum.reduce(&MapSet.union/2) |> MapSet.size(),
          line_sets |> Enum.map(&elem(&1, 0)) |> Enum.reduce(&MapSet.union/2) |> MapSet.size()
        }
    end
  end

  @doc """
  The published totals of every run of the project that gathered coverage,
  one row per run with the scheme they were measured for and whether the run
  was partial. A run gathered coverage when it measured a product line or its
  reports listed a file: a run whose product code all came from the binary
  cache without counters lists only its test files, and what it took from the
  cache is still the commit's to judge (`Tuist.Tests.Coverage.Instrumentation`).
  Rows published before the count existed carry 0 and count by their lines.
  `shas:` narrows it to the runs of those commits, read through
  the table's index on the SHA rather than across the project's history.
  """
  def run_totals_query(project_id, opts \\ []) do
    project_id
    |> run_totals_base(Keyword.get(opts, :shas))
    |> select([c], %{
      test_run_id: c.test_run_id,
      scheme: fragment("argMax(?, ?)", c.scheme, c.version),
      build_system: fragment("argMax(?, ?)", c.build_system, c.version),
      git_commit_sha: fragment("argMax(?, ?)", c.git_commit_sha, c.version),
      covered_lines: fragment("argMax(?, ?)", c.covered_lines, c.version),
      executable_lines: fragment("argMax(?, ?)", c.executable_lines, c.version),
      partial: fragment("argMax(?, ?)", c.partial, c.version)
    })
  end

  @doc """
  The project's `coverage_runs` grouped by run and kept to the runs that
  gathered coverage, as `run_totals_query/2` keeps them, for a reader that
  selects its own columns.
  """
  def gathered_runs_query(project_id), do: run_totals_base(project_id, nil)

  defp run_totals_base(project_id, nil) do
    from(c in CoverageRun,
      where: c.project_id == ^project_id,
      group_by: c.test_run_id,
      having:
        fragment("argMax(?, ?)", c.executable_lines, c.version) > 0 or
          fragment("argMax(?, ?)", c.files, c.version) > 0
    )
  end

  defp run_totals_base(project_id, shas), do: where(run_totals_base(project_id, nil), [c], c.git_commit_sha in ^shas)

  @doc """
  Every product file of the run with its shards' reports merged: path, blob,
  targets and line counts, without the line data. What a comparison of two
  runs reads.
  """
  def merged_files(project_id, test_run_id, opts \\ []) do
    ClickHouseRepo.all(
      from(f in subquery(merged_files_query(project_id, test_run_id, excluded(project_id, opts))), order_by: f.path)
    )
  end

  @retention_tables %{
    files: ["coverage_files", "coverage_run_files", "coverage_file_layouts", "test_impact_diffs"],
    runs: ["coverage_runs", "test_impact_runs"]
  }

  @commit_retention_tables ["coverage_file_deltas", "coverage_commit_targets"]

  @doc """
  Sets each coverage table's time-to-live to the configured retention (see
  `Tuist.Environment.coverage_retention_days/1`) and returns the days applied
  per table: the detail by when it was inserted, and the commits' file
  deltas and targets with the commit totals, by when the commit was made
  (`Tuist.Environment.coverage_commit_retention_days/1`). The tables get it
  at creation; this re-applies it after the configuration changed. The
  commits' uploaded listings, the per-test evidence in `coverage_files`
  (`Tuist.Tests.Coverage.Evidence.retention_days/0`) and the target sources
  keep their own fixed days (`Tuist.GitHistory.listing_retention_days/0`).
  """
  def apply_retention do
    detail =
      for {kind, days} <- Environment.coverage_retention_days(), table <- Map.fetch!(@retention_tables, kind) do
        IngestRepo.query!("ALTER TABLE #{table} MODIFY TTL #{detail_ttl(table, days)}")
        {table, days}
      end

    days = Environment.coverage_commit_retention_days().commits

    commits =
      for table <- @commit_retention_tables do
        IngestRepo.query!("ALTER TABLE #{table} MODIFY TTL toDateTime(committed_at) + INTERVAL #{days} DAY")
        {table, days}
      end

    listing_days = GitHistory.listing_retention_days()
    IngestRepo.query!("ALTER TABLE git_commit_files MODIFY TTL toDateTime(inserted_at) + INTERVAL #{listing_days} DAY")

    detail ++ commits ++ [{"git_commit_files", listing_days}]
  end

  # The run's own rows keep the file retention; its evidence (every other
  # scope) expires sooner, whatever that retention is.
  defp detail_ttl("coverage_files", days) do
    "toDateTime(inserted_at) + INTERVAL #{Evidence.retention_days()} DAY DELETE WHERE scope_kind != 'run', " <>
      "toDateTime(inserted_at) + INTERVAL #{days} DAY"
  end

  # A week's layouts outlive the run rows of its last day.
  defp detail_ttl("coverage_file_layouts", days), do: "epoch + INTERVAL #{days + 8} DAY"

  defp detail_ttl(_table, days), do: "toDateTime(inserted_at) + INTERVAL #{days} DAY"

  def percentage(_covered, 0), do: 0.0
  def percentage(_covered, nil), do: 0.0
  def percentage(covered, executable), do: Float.round(covered / executable * 100, 1)

  # A row per shard that compiled the file: the counts add up. When no report
  # has the file's lines (its archive entry was missing), the counts are the
  # report's, as in `merged_files_query/2`, and `lines` is empty.
  @doc false
  def detail(path, rows) do
    lines =
      rows
      |> Enum.flat_map(&Enum.zip(&1.line_numbers, &1.execution_counts))
      |> Enum.reduce(%{}, fn {line, count}, acc -> Map.update(acc, line, count, &(&1 + count)) end)
      |> Enum.sort()

    {covered_lines, executable_lines} =
      if lines == [] do
        {rows |> Enum.map(& &1.covered_lines) |> Enum.max(), rows |> Enum.map(& &1.executable_lines) |> Enum.max()}
      else
        {Enum.count(lines, fn {_line, count} -> count > 0 end), length(lines)}
      end

    %{
      path: path,
      git_blob_id: rows |> hd() |> Map.get(:git_blob_id),
      targets: rows |> Enum.flat_map(& &1.targets) |> Enum.uniq() |> Enum.sort(),
      covered_lines: covered_lines,
      executable_lines: executable_lines,
      lines: lines,
      functions: rows |> merged_functions() |> cover_functions(lines)
    }
  end

  @doc """
  The functions' covered lines read off the file's merged `{line, count}`
  pairs. xccov counts a function's executable lines from its first line on,
  its nested closures' included, so they are the first `executable_lines`
  executable lines at or after `line_number`: which of them ran is exact
  however many reports covered the function. A function whose lines are not
  all there, or whose count falls short of what one report alone covered,
  keeps the figure `merged_functions/1` gave it.
  """
  def cover_functions(functions, []), do: functions

  def cover_functions(functions, lines) do
    Enum.map(functions, fn function ->
      span =
        lines
        |> Enum.drop_while(fn {line, _count} -> line < function.line_number end)
        |> Enum.take(function.executable_lines)

      covered = Enum.count(span, fn {_line, count} -> count > 0 end)

      if length(span) == function.executable_lines and covered >= function.confirmed_lines,
        do: %{function | covered_lines: covered},
        else: function
    end)
  end

  # A function's lines as the reports give them: its covered lines are exact
  # when at most one report covered any, and nil (unknown) otherwise, until
  # `cover_functions/2` reads them off the file's lines; `confirmed_lines`,
  # the most one report covered, is what that reading must reach. Calls add
  # up across reports.
  defp merged_functions(rows) do
    rows
    |> Enum.flat_map(fn row ->
      Enum.zip([
        row.function_names,
        row.function_line_numbers,
        row.function_execution_counts,
        row.function_covered_lines,
        row.function_executable_lines
      ])
    end)
    |> Enum.group_by(fn {name, line, _, _, _} -> {name, line} end)
    |> Enum.map(fn {{name, line}, entries} ->
      covered_lines =
        case entries |> Enum.map(&elem(&1, 3)) |> Enum.filter(&(&1 > 0)) do
          [] -> 0
          [covered] -> covered
          _ -> nil
        end

      %{
        name: name,
        line_number: line,
        execution_count: entries |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
        covered_lines: covered_lines,
        confirmed_lines: entries |> Enum.map(&elem(&1, 3)) |> Enum.max(),
        executable_lines: entries |> Enum.map(&elem(&1, 4)) |> Enum.max()
      }
    end)
    |> Enum.sort_by(&{&1.line_number, &1.name})
  end

  # The run-scoped rows of each shard's newest report, synced or not: a shard
  # publishing its totals covers the reports the others made so far, and
  # `Workers.TotalsWorker` waits for those to reach every replica too.
  defp report_files(project_id, test_run_id), do: report_files_for_runs(project_id, [test_run_id], pinned: false)

  @doc """
  The rows of the given runs' reports their published totals cover, one per
  shard, each with its file version's blob, lines and functions and its
  counts laid out against them (zeros where the run stored none): what every
  reader of a run's, or a commit's, coverage starts from. A subquery, so a
  reader's filter on the path reaches both the rows and the layouts it joins.
  `lines: false` leaves the layouts out, for a reader of paths, targets and
  counts only.

  The reports are the ones the run's newest `coverage_runs` row pins
  (`report_shards`, `report_inserted_at`), which every replica held when it
  was written: a replica that already holds a retried shard's newer report
  keeps serving the pinned one until totals covering the retry are written.
  `pinned: false` reads each shard's newest report instead, synced or not,
  for the write path, whose totals cover the reports the others made so far.
  """
  def report_files_for_runs(project_id, test_run_ids, opts \\ []) do
    rows = from(f in CoverageRunFile, where: f.project_id == ^project_id and f.test_run_id in ^test_run_ids)

    latest_reports =
      if Keyword.get(opts, :pinned, true),
        do: pinned_reports(project_id, test_run_ids),
        else:
          from(f in rows,
            group_by: [f.test_run_id, f.shard_index],
            select: %{test_run_id: f.test_run_id, shard_index: f.shard_index, inserted_at: max(f.inserted_at)}
          )

    reported =
      from(f in rows,
        join: r in subquery(latest_reports),
        on: r.test_run_id == f.test_run_id and r.shard_index == f.shard_index and r.inserted_at == f.inserted_at,
        select: %{
          test_run_id: f.test_run_id,
          shard_index: f.shard_index,
          partial: f.partial,
          path: f.path,
          in_repository: f.in_repository,
          is_test: f.is_test,
          targets: f.targets,
          covered_lines: f.covered_lines,
          executable_lines: f.executable_lines,
          inserted_at: f.inserted_at
        }
      )

    if Keyword.get(opts, :lines, true) do
      # One read of the runs' rows names the layouts by week and id; two
      # (`epoch IN` and `layout_id IN`) read them twice for a looser filter.
      layouts =
        from(l in CoverageFileLayout,
          where:
            l.project_id == ^project_id and
              fragment(
                "(?, ?) IN ?",
                l.epoch,
                l.layout_id,
                subquery(select(rows, [f], %{epoch: f.epoch, layout_id: f.layout_id}))
              )
        )

      subquery(
        from([f, _r] in reported,
          left_join: l in subquery(layouts),
          hints: ["ANY"],
          on: l.path == f.path and l.layout_id == f.layout_id,
          select_merge: %{
            git_blob_id: l.git_blob_id,
            line_numbers: l.line_numbers,
            execution_counts: fragment("arrayResize(?, length(?))", f.execution_counts, l.line_numbers),
            function_names: l.function_names,
            function_line_numbers: l.function_line_numbers,
            function_execution_counts:
              fragment("arrayResize(?, length(?))", f.function_execution_counts, l.function_names),
            function_covered_lines: fragment("arrayResize(?, length(?))", f.function_covered_lines, l.function_names),
            function_executable_lines: l.function_executable_lines
          }
        )
      )
    else
      subquery(reported)
    end
  end

  @doc """
  `report_files_for_runs/3`'s choice of reports as raw SQL, for raw queries
  that read `coverage_run_files` themselves (`Tuist.TestImpactAnalysis.Snapshots`):
  the `(test_run_id, shard_index, inserted_at)` of each shard's report the
  runs' newest totals pin, read from `coverage_runs` alone. It reads the
  parameters `{project_id:Int64}` and `{run_ids:Array(UUID)}`, so a query
  filters its rows with
  `(test_run_id, shard_index, inserted_at) IN (\#{pinned_reports_sql()})`.
  """
  def pinned_reports_sql do
    """
    SELECT test_run_id, tupleElement(pin, 1) AS shard_index, tupleElement(pin, 2) AS report_inserted_at
    FROM (
      SELECT test_run_id, arrayJoin(arrayZip(argMax(report_shards, version), argMax(report_inserted_at, version))) AS pin
      FROM coverage_runs
      WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
      GROUP BY test_run_id
    )
    """
  end

  # Each shard's report the run's newest totals pin (`pinned_reports_sql/0`
  # is the same as raw SQL), one row per pinned shard. A shard the pins leave
  # out has no synced report yet and is read as not reported; a run whose
  # totals pin nothing (none of its reports listed a file) reads no rows.
  # Every run's totals carry pins: `Workers.PinsBackfillWorker` wrote them for
  # the runs reported before.
  defp pinned_reports(project_id, test_run_ids) do
    pins =
      from(c in CoverageRun,
        where: c.project_id == ^project_id and c.test_run_id in ^test_run_ids,
        group_by: c.test_run_id,
        select: %{
          test_run_id: c.test_run_id,
          pin:
            fragment(
              "arrayJoin(arrayZip(argMax(?, ?), argMax(?, ?)))",
              c.report_shards,
              c.version,
              c.report_inserted_at,
              c.version
            )
        }
      )

    from(p in subquery(pins),
      select: %{
        test_run_id: p.test_run_id,
        shard_index: fragment("tupleElement(?, 1)", p.pin),
        inserted_at: fragment("tupleElement(?, 2)", p.pin)
      }
    )
  end

  @doc """
  An Ecto query as SQL with its parameters inlined, for a raw query to read
  it as a subquery, as the carried fold (`Coverage.Reported`) and the delta
  writes (`Coverage.Deltas`) read the runs' rows. Lists are inlined as one
  array each (`Tuist.ClickHouse.ArrayInParams`), so the SQL's size grows
  with them: keep to queries over a few runs.
  """
  def inline_sql(%Ecto.Query{} = query), do: inline_sql(subquery(query))

  # A subquery names its columns, which a query's own map select doesn't.
  def inline_sql(%Ecto.SubQuery{} = query),
    do: Ecto.Adapters.ClickHouse.to_inline_sql(:all, ArrayInParams.rewrite(from(f in query, select: f)))

  # One row per path, its shards' reports merged: the lines are the union
  # across shards. A file whose archive entry was missing keeps the counts the
  # report gave it, since there are no lines to merge.
  defp merged_files_query(project_id, test_run_id, excluded),
    do: merged_files_query_for_runs(project_id, [test_run_id], excluded)

  @doc """
  Every product file of the given runs with their reports merged per path,
  as `merged_files/3` reads one run: a line is covered when any report
  covered it, a file counts once however many runs compiled it. What a
  commit's coverage is: the union of the runs that measured it.
  """
  def merged_files_query_for_runs(project_id, test_run_ids, excluded) do
    from(f in without_excluded(report_files_for_runs(project_id, test_run_ids), excluded),
      where: not f.is_test,
      group_by: f.path,
      select: %{
        path: f.path,
        # The newest report's blob: `any` let two reads of one commit pick
        # different blobs when its runs disagreed.
        git_blob_id: fragment("argMaxIf(?, ?, ? != '')", f.git_blob_id, f.inserted_at, f.git_blob_id),
        targets: fragment("groupUniqArrayArray(?)", f.targets),
        executable_lines:
          fragment(
            "toUInt64(if(max(length(?)) = 0, max(?), length(groupUniqArrayArray(?))))",
            f.line_numbers,
            f.executable_lines,
            f.line_numbers
          ),
        covered_lines:
          fragment(
            "toUInt64(if(max(length(?)) = 0, max(?), length(groupUniqArrayArray(arrayFilter((l, c) -> c > 0, ?, ?)))))",
            f.line_numbers,
            f.covered_lines,
            f.line_numbers,
            f.execution_counts
          )
      }
    )
  end

  @doc false
  def excluded(project_id, opts) do
    Keyword.get_lazy(opts, :excluded, fn -> ExcludedPaths.pattern_for_project(project_id) end)
  end

  @doc false
  def without_excluded(query, nil), do: query
  def without_excluded(query, pattern), do: from(f in query, where: not fragment("match(?, ?)", f.path, ^pattern))

  defp file_row(file) do
    functions = value(file, :functions, [])

    git_blob_id = value(file, :git_blob_id, "")

    path = value(file, :path, "")

    %{
      path: path,
      in_repository: git_blob_id != "" and not String.starts_with?(path, "/"),
      git_blob_id: git_blob_id,
      targets: value(file, :targets, []),
      is_test: value(file, :is_test, false),
      covered_lines: value(file, :covered_lines, 0),
      executable_lines: value(file, :executable_lines, 0),
      line_numbers: value(file, :line_numbers, []),
      execution_counts: value(file, :execution_counts, []),
      function_names: Enum.map(functions, &value(&1, :name, "")),
      function_line_numbers: Enum.map(functions, &value(&1, :line_number, 0)),
      function_execution_counts: Enum.map(functions, &value(&1, :execution_count, 0)),
      function_covered_lines: Enum.map(functions, &value(&1, :covered_lines, 0)),
      function_executable_lines: Enum.map(functions, &value(&1, :executable_lines, 0))
    }
  end

  defp value(map, key, default) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key)) || default
      found -> found
    end
  end
end
