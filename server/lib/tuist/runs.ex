defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runs.Build
  alias Tuist.Runs.BuildFile
  alias Tuist.Runs.BuildIssue
  alias Tuist.Runs.BuildTarget
  alias Tuist.Runs.CacheableTask
  alias Tuist.Runs.CASOutput
  alias Tuist.Runs.FlakyTestCase
  alias Tuist.Runs.Test
  alias Tuist.Runs.TestCase
  alias Tuist.Runs.TestCaseFailure
  alias Tuist.Runs.TestCaseRun
  alias Tuist.Runs.TestCaseRunRepetition
  alias Tuist.Runs.TestModuleRun
  alias Tuist.Runs.TestSuiteRun

  def valid_ci_providers, do: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

  def get_build(id) do
    Repo.get(Build, id)
  end

  def get_test(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    query =
      from(t in Test,
        hints: ["FINAL"],
        where: t.id == ^id,
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test -> {:ok, Repo.preload(test, preload)}
    end
  end

  def get_latest_test_by_build_run_id(build_run_id) do
    query =
      from(t in Test,
        hints: ["FINAL"],
        where: t.build_run_id == ^build_run_id,
        order_by: [desc: t.ran_at],
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test -> {:ok, test}
    end
  end

  def list_test_runs(attrs) do
    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(Test, attrs, for: Test)

    results = Repo.preload(results, :ran_by_account)

    {results, meta}
  end

  def create_build(attrs) do
    cacheable_tasks = Map.get(attrs, :cacheable_tasks, [])
    cas_outputs = Map.get(attrs, :cas_outputs, [])

    cacheable_task_counts = %{
      cacheable_tasks_count: Map.get(attrs, :cacheable_tasks_count) || length(cacheable_tasks),
      cacheable_task_local_hits_count:
        Map.get(attrs, :cacheable_task_local_hits_count) ||
          Enum.count(cacheable_tasks, &(&1.status == :hit_local)),
      cacheable_task_remote_hits_count:
        Map.get(attrs, :cacheable_task_remote_hits_count) ||
          Enum.count(cacheable_tasks, &(&1.status == :hit_remote))
    }

    attrs = Map.merge(attrs, cacheable_task_counts)

    case %Build{}
         |> Build.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, build} ->
        Task.await_many(
          [
            Task.async(fn -> create_build_issues(build, attrs.issues) end),
            Task.async(fn -> create_build_files(build, attrs.files) end),
            Task.async(fn -> create_build_targets(build, attrs.targets) end),
            Task.async(fn -> create_cacheable_tasks(build, cacheable_tasks) end),
            Task.async(fn -> create_cas_outputs(build, cas_outputs) end)
          ],
          30_000
        )

        build = Repo.preload(build, project: :account)

        Tuist.PubSub.broadcast(
          build,
          "#{build.project.account.name}/#{build.project.name}",
          :build_created
        )

        {:ok, build}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_build_files(build, files) do
    files =
      Enum.map(files, fn file_attrs ->
        %{
          build_run_id: build.id,
          type:
            case file_attrs.type do
              :swift -> 0
              :c -> 1
            end,
          path: file_attrs.path,
          target: file_attrs.target,
          project: file_attrs.project,
          compilation_duration: file_attrs.compilation_duration
        }
      end)

    IngestRepo.insert_all(BuildFile, files)
  end

  defp create_build_targets(build, targets) do
    targets = Enum.map(targets, &BuildTarget.changeset(build.id, &1))

    IngestRepo.insert_all(BuildTarget, targets)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp create_build_issues(build, issues) do
    issues =
      Enum.map(issues, fn issue_attrs ->
        %{
          build_run_id: build.id,
          type:
            case issue_attrs.type do
              :warning -> 0
              :error -> 1
            end,
          target: issue_attrs.target,
          project: issue_attrs.project,
          title: issue_attrs.title,
          signature: issue_attrs.signature,
          step_type:
            case issue_attrs.step_type do
              :c_compilation -> 0
              :swift_compilation -> 1
              :script_execution -> 2
              :create_static_library -> 3
              :linker -> 4
              :copy_swift_libs -> 5
              :compile_assets_catalog -> 6
              :compile_storyboard -> 7
              :write_auxiliary_file -> 8
              :link_storyboards -> 9
              :copy_resource_file -> 10
              :merge_swift_module -> 11
              :xib_compilation -> 12
              :swift_aggregated_compilation -> 13
              :precompile_bridging_header -> 14
              :other -> 15
              :validate_embedded_binary -> 16
              :validate -> 17
            end,
          path: Map.get(issue_attrs, :path),
          message: Map.get(issue_attrs, :message),
          starting_line: issue_attrs.starting_line,
          ending_line: issue_attrs.ending_line,
          starting_column: issue_attrs.starting_column,
          ending_column: issue_attrs.ending_column
        }
      end)

    IngestRepo.insert_all(
      BuildIssue,
      issues
    )
  end

  defp create_cacheable_tasks(build, tasks) do
    tasks =
      tasks
      |> Enum.map(&CacheableTask.changeset(build.id, &1))
      |> Enum.map(&Ecto.Changeset.apply_changes/1)
      |> Enum.map(fn struct ->
        %{
          type: struct.type,
          status: struct.status,
          key: struct.key,
          build_run_id: struct.build_run_id,
          read_duration: struct.read_duration,
          write_duration: struct.write_duration,
          description: struct.description,
          cas_output_node_ids: struct.cas_output_node_ids,
          inserted_at: struct.inserted_at
        }
      end)

    IngestRepo.insert_all(CacheableTask, tasks)
  end

  defp create_cas_outputs(build, outputs) do
    outputs =
      outputs
      |> Enum.map(&CASOutput.changeset(build.id, &1))
      |> Enum.map(&Ecto.Changeset.apply_changes/1)
      |> Enum.map(fn struct ->
        %{
          node_id: struct.node_id,
          checksum: struct.checksum,
          size: struct.size,
          duration: struct.duration,
          compressed_size: struct.compressed_size,
          operation: struct.operation,
          type: struct.type,
          build_run_id: struct.build_run_id,
          inserted_at: struct.inserted_at
        }
      end)

    IngestRepo.insert_all(CASOutput, outputs)
  end

  def list_build_files(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(BuildFile, attrs, for: BuildFile)
  end

  def list_build_targets(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(BuildTarget, attrs, for: BuildTarget)
  end

  def list_test_case_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestCaseRun, attrs, for: TestCaseRun)
  end

  def get_test_run_failures_count(test_run_id) do
    query =
      from f in TestCaseFailure,
        join: tcr in TestCaseRun,
        on: f.test_case_run_id == tcr.id,
        where: tcr.test_run_id == ^test_run_id,
        select: count(f.id)

    ClickHouseRepo.one(query) || 0
  end

  def list_test_run_failures(test_run_id, attrs) do
    query =
      from f in TestCaseFailure,
        join: tcr in TestCaseRun,
        on: f.test_case_run_id == tcr.id,
        where: tcr.test_run_id == ^test_run_id,
        select: %{
          id: f.id,
          test_case_run_id: f.test_case_run_id,
          message: f.message,
          path: f.path,
          line_number: f.line_number,
          issue_type: f.issue_type,
          inserted_at: f.inserted_at,
          test_case_name: tcr.name,
          test_module_name: tcr.module_name,
          test_suite_name: tcr.suite_name
        }

    Tuist.ClickHouseFlop.validate_and_run!(query, attrs, for: TestCaseFailure)
  end

  def list_test_suite_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestSuiteRun, attrs, for: TestSuiteRun)
  end

  def list_test_module_runs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestModuleRun, attrs, for: TestModuleRun)
  end

  def list_cacheable_tasks(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(CacheableTask, attrs, for: CacheableTask)
  end

  def list_cas_outputs(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(CASOutput, attrs, for: CASOutput)
  end

  def get_cas_outputs_by_node_ids(build_run_id, node_ids, opts \\ []) when is_list(node_ids) do
    distinct = Keyword.get(opts, :distinct, false)

    if Enum.empty?(node_ids) do
      []
    else
      query = from(c in CASOutput, where: c.build_run_id == ^build_run_id and c.node_id in ^node_ids)

      query =
        if distinct do
          from(c in query, distinct: c.node_id)
        else
          query
        end

      ClickHouseRepo.all(query)
    end
  end

  def cas_output_metrics(build_run_id) do
    query = """
    SELECT
      countIf(operation = 'download') as download_count,
      countIf(operation = 'upload') as upload_count,
      sumIf(size, operation = 'download') as download_bytes,
      sumIf(size, operation = 'upload') as upload_bytes,
      sumIf(size, operation = 'download' AND duration > 0) / sumIf(duration, operation = 'download' AND duration > 0) * 1000 as time_weighted_avg_download_throughput,
      sumIf(size, operation = 'upload' AND duration > 0) / sumIf(duration, operation = 'upload' AND duration > 0) * 1000 as time_weighted_avg_upload_throughput
    FROM cas_outputs
    WHERE build_run_id = {build_run_id:UUID}
    """

    {:ok,
     %{
       rows: [
         [
           download_count,
           upload_count,
           download_bytes,
           upload_bytes,
           time_weighted_avg_download_throughput,
           time_weighted_avg_upload_throughput
         ]
       ]
     }} = ClickHouseRepo.query(query, %{build_run_id: build_run_id})

    %{
      download_count: download_count,
      upload_count: upload_count,
      download_bytes: download_bytes || 0,
      upload_bytes: upload_bytes || 0,
      time_weighted_avg_download_throughput: time_weighted_avg_download_throughput || 0,
      time_weighted_avg_upload_throughput: time_weighted_avg_upload_throughput || 0
    }
  end

  def cacheable_task_latency_metrics(build_run_id) do
    query = """
    SELECT
      avg(read_duration) as avg_read_duration,
      avg(write_duration) as avg_write_duration,
      quantile(0.99)(read_duration) as p99_read_duration,
      quantile(0.99)(write_duration) as p99_write_duration,
      quantile(0.90)(read_duration) as p90_read_duration,
      quantile(0.90)(write_duration) as p90_write_duration,
      quantile(0.50)(read_duration) as p50_read_duration,
      quantile(0.50)(write_duration) as p50_write_duration
    FROM cacheable_tasks
    WHERE build_run_id = {build_run_id:UUID}
    AND (read_duration IS NOT NULL OR write_duration IS NOT NULL)
    """

    {:ok,
     %{
       rows: [
         [
           avg_read_duration,
           avg_write_duration,
           p99_read_duration,
           p99_write_duration,
           p90_read_duration,
           p90_write_duration,
           p50_read_duration,
           p50_write_duration
         ]
       ]
     }} = ClickHouseRepo.query(query, %{build_run_id: build_run_id})

    %{
      avg_read_duration: avg_read_duration || 0,
      avg_write_duration: avg_write_duration || 0,
      p99_read_duration: p99_read_duration || 0,
      p99_write_duration: p99_write_duration || 0,
      p90_read_duration: p90_read_duration || 0,
      p90_write_duration: p90_write_duration || 0,
      p50_read_duration: p50_read_duration || 0,
      p50_write_duration: p50_write_duration || 0
    }
  end

  def list_build_runs(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Build
    |> preload(^preload)
    |> Flop.validate_and_run!(attrs, for: Build)
  end

  def recent_build_status_counts(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)
    order = Keyword.get(opts, :order, :desc)

    subquery =
      from(b in Build)
      |> where([b], b.project_id == ^project_id)
      |> order_by([b], [{^order, b.inserted_at}])
      |> limit(^limit)
      |> select([b], b.status)

    from(s in subquery(subquery))
    |> select([s], %{
      successful_count: count(fragment("CASE WHEN ? = 0 THEN 1 END", s.status)),
      failed_count: count(fragment("CASE WHEN ? = 1 THEN 1 END", s.status))
    })
    |> Repo.one()
  end

  def project_build_schemes(%Project{} = project) do
    from(b in Build)
    |> where([b], b.project_id == ^project.id)
    |> where([b], not is_nil(b.scheme))
    |> where([b], b.inserted_at > ^DateTime.add(DateTime.utc_now(), -30, :day))
    |> distinct([b], b.scheme)
    |> select([b], b.scheme)
    |> Repo.all()
  end

  def project_build_configurations(%Project{} = project) do
    from(b in Build)
    |> where([b], b.project_id == ^project.id)
    |> where([b], not is_nil(b.configuration))
    |> where([b], b.inserted_at > ^DateTime.add(DateTime.utc_now(), -30, :day))
    |> distinct([b], b.configuration)
    |> select([b], b.configuration)
    |> Repo.all()
  end

  @doc """
  Constructs a CI run URL based on the CI provider and metadata.
  Returns nil if the build doesn't have complete CI information.
  """
  def build_ci_run_url(%Build{} = build) do
    Tuist.VCS.ci_run_url(build)
  end

  @doc """
  Constructs a CI run URL for a test run based on the CI provider and metadata.
  Returns nil if the test doesn't have complete CI information.
  """
  def test_ci_run_url(%Test{} = test) do
    Tuist.VCS.ci_run_url(%{
      ci_provider: normalize_ci_provider(test.ci_provider),
      ci_run_id: test.ci_run_id,
      ci_project_handle: test.ci_project_handle,
      ci_host: test.ci_host
    })
  end

  defp normalize_ci_provider(nil), do: nil
  defp normalize_ci_provider(""), do: nil

  defp normalize_ci_provider(provider) when is_binary(provider) do
    if provider in valid_ci_providers() do
      String.to_existing_atom(provider)
    end
  end

  defp normalize_ci_provider(provider) when is_atom(provider), do: provider

  def create_test(attrs) do
    test_modules = Map.get(attrs, :test_modules, [])
    is_ci = Map.get(attrs, :is_ci, false)
    has_flaky_tests = has_any_flaky_test_case?(test_modules)

    # Only mark the Test as flaky if it's a CI run
    attrs =
      if has_flaky_tests and is_ci do
        Map.put(attrs, :is_flaky, true)
      else
        attrs
      end

    case %Test{}
         |> Test.create_changeset(attrs)
         |> IngestRepo.insert() do
      {:ok, test} ->
        create_test_modules(test, test_modules)

        project = Tuist.Projects.get_project_by_id(test.project_id)

        Tuist.PubSub.broadcast(
          test,
          "#{project.account.name}/#{project.name}",
          :test_created
        )

        {:ok, test}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp has_any_flaky_test_case?(test_modules) do
    Enum.any?(test_modules, fn module_attrs ->
      test_cases = Map.get(module_attrs, :test_cases, [])

      Enum.any?(test_cases, fn case_attrs ->
        repetitions = Map.get(case_attrs, :repetitions, [])
        original_status = Map.get(case_attrs, :status)

        Enum.any?(repetitions) and
          Enum.any?(repetitions, fn rep -> Map.get(rep, :status) == "failure" end) and
          original_status == "success"
      end)
    end)
  end

  @doc """
  Creates test cases and returns a map of {name, module_name, suite_name} => test_case_id.
  Uses deterministic UUIDs based on the test case identity, so duplicates are handled
  by ClickHouse's ReplacingMergeTree engine (keeps the row with the latest inserted_at).

  Each test case data map should contain:
  - :name, :module_name, :suite_name - identity fields
  - :status, :duration, :ran_at - latest run data
  """
  def create_test_cases(project_id, test_case_data_list) do
    now = NaiveDateTime.utc_now()

    test_case_ids_with_data =
      Enum.map(test_case_data_list, fn data ->
        id = generate_test_case_id(project_id, data.name, data.module_name, data.suite_name)
        {id, data}
      end)

    test_case_ids = Enum.map(test_case_ids_with_data, fn {id, _} -> id end)

    existing_data = fetch_existing_test_case_data(project_id, test_case_ids)

    test_cases =
      Enum.map(test_case_ids_with_data, fn {id, data} ->
        existing = Map.get(existing_data, id, %{recent_durations: []})
        new_durations = Enum.take([data.duration | existing.recent_durations], 50)

        new_avg =
          if Enum.empty?(new_durations),
            do: 0,
            else: div(Enum.sum(new_durations), length(new_durations))

        current_is_flaky = Map.get(data, :is_flaky, false)
        existing_is_flaky = Map.get(existing, :is_flaky, false)

        %{
          id: id,
          name: data.name,
          module_name: data.module_name,
          suite_name: data.suite_name,
          project_id: project_id,
          last_status: data.status,
          last_duration: data.duration,
          last_ran_at: data.ran_at,
          is_flaky: current_is_flaky or existing_is_flaky,
          inserted_at: now,
          recent_durations: new_durations,
          avg_duration: new_avg
        }
      end)

    IngestRepo.insert_all(TestCase, test_cases)

    Map.new(test_cases, fn tc ->
      {{tc.name, tc.module_name, tc.suite_name}, tc.id}
    end)
  end

  defp fetch_existing_test_case_data(_project_id, []), do: %{}

  defp fetch_existing_test_case_data(project_id, test_case_ids) do
    query =
      from(tc in TestCase,
        hints: ["FINAL"],
        where: tc.project_id == ^project_id,
        where: tc.id in ^test_case_ids,
        select: %{id: tc.id, recent_durations: tc.recent_durations, is_flaky: tc.is_flaky}
      )

    query
    |> IngestRepo.all()
    |> Map.new(fn row -> {row.id, row} end)
  end

  defp generate_test_case_id(project_id, name, module_name, suite_name) do
    identity = "#{project_id}:#{name}:#{module_name}:#{suite_name}"

    <<a::32, b::16, c::16, d::16, e::48>> =
      :md5
      |> :crypto.hash(identity)
      |> binary_part(0, 16)

    # Format as UUID v4 (set version and variant bits)
    Ecto.UUID.cast!(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>)
  end

  @doc """
  Gets a test case by its UUID with all denormalized fields.
  Returns {:ok, test_case} or {:error, :not_found}.
  """
  def get_test_case_by_id(id) do
    query =
      from(tc in TestCase,
        hints: ["FINAL"],
        where: tc.id == ^id,
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test_case -> {:ok, test_case}
    end
  end

  @doc """
  Unmarks a test case as flaky by inserting a new row with is_flaky set to false.
  ClickHouse ReplacingMergeTree will keep the most recent row.
  """
  def unmark_test_case_as_flaky(test_case_id) do
    with {:ok, test_case} <- get_test_case_by_id(test_case_id) do
      updated_test_case = %{
        id: test_case.id,
        name: test_case.name,
        module_name: test_case.module_name,
        suite_name: test_case.suite_name,
        project_id: test_case.project_id,
        last_status: test_case.last_status,
        last_duration: test_case.last_duration,
        last_ran_at: test_case.last_ran_at,
        is_flaky: false,
        inserted_at: NaiveDateTime.utc_now(),
        recent_durations: test_case.recent_durations,
        avg_duration: test_case.avg_duration
      }

      IngestRepo.insert_all(TestCase, [updated_test_case])
      {:ok, %{test_case | is_flaky: false}}
    end
  end

  @doc """
  Marks a test case as flaky by inserting a new row with is_flaky set to true.
  ClickHouse ReplacingMergeTree will keep the most recent row.
  """
  def mark_test_case_as_flaky(test_case_id) do
    with {:ok, test_case} <- get_test_case_by_id(test_case_id) do
      updated_test_case = %{
        id: test_case.id,
        name: test_case.name,
        module_name: test_case.module_name,
        suite_name: test_case.suite_name,
        project_id: test_case.project_id,
        last_status: test_case.last_status,
        last_duration: test_case.last_duration,
        last_ran_at: test_case.last_ran_at,
        is_flaky: true,
        inserted_at: NaiveDateTime.utc_now(),
        recent_durations: test_case.recent_durations,
        avg_duration: test_case.avg_duration
      }

      IngestRepo.insert_all(TestCase, [updated_test_case])
      {:ok, %{test_case | is_flaky: true}}
    end
  end

  @doc """
  Lists test case runs for a specific test case by its UUID.
  Returns a tuple of {test_case_runs, meta} with pagination info.
  """
  def list_test_case_runs_by_test_case_id(test_case_id, attrs) do
    base_query =
      from(tcr in TestCaseRun,
        hints: ["FINAL"],
        where: tcr.test_case_id == ^test_case_id
      )

    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRun)

    results = Repo.preload(results, :ran_by_account)

    {results, meta}
  end

  defp create_test_modules(test, test_modules) do
    Enum.each(test_modules, fn module_attrs ->
      module_id = UUIDv7.generate()
      module_name = Map.get(module_attrs, :name)

      test_suites = Map.get(module_attrs, :test_suites, [])
      test_cases = Map.get(module_attrs, :test_cases, [])

      test_suite_count = length(test_suites)
      test_case_count = length(test_cases)

      avg_test_case_duration = calculate_avg_test_case_duration(test_cases)

      # Pre-compute all test_case_run statuses and flaky flags (including cross-run flaky detection)
      test_case_run_data =
        compute_all_test_case_run_statuses(test, test_cases, module_name)

      # Aggregate is_flaky from test_case_run data
      module_is_flaky = compute_aggregate_is_flaky(Map.values(test_case_run_data))

      module_run_attrs = %{
        id: module_id,
        name: module_name,
        test_run_id: test.id,
        status: Map.get(module_attrs, :status),
        is_flaky: module_is_flaky,
        duration: Map.get(module_attrs, :duration, 0),
        test_suite_count: test_suite_count,
        test_case_count: test_case_count,
        avg_test_case_duration: avg_test_case_duration,
        inserted_at: NaiveDateTime.utc_now()
      }

      {:ok, _module_run} =
        %TestModuleRun{}
        |> TestModuleRun.create_changeset(module_run_attrs)
        |> IngestRepo.insert()

      suite_name_to_id = create_test_suites(test, module_id, test_suites, test_cases, test_case_run_data)

      create_test_cases_for_module(
        test,
        module_id,
        test_cases,
        suite_name_to_id,
        module_name,
        test_case_run_data
      )
    end)
  end

  defp compute_all_test_case_run_statuses(test, test_cases, module_name) do
    {test_case_run_data, historical_flaky_ids} =
      Enum.reduce(test_cases, {%{}, []}, fn case_attrs, {data_acc, ids_acc} ->
        case_name = Map.get(case_attrs, :name)
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""

        # Generate deterministic test_case_id
        test_case_id = generate_test_case_id(test.project_id, case_name, module_name, suite_name)

        # Compute status and is_flaky
        {status, is_flaky} = compute_test_case_run_status_and_flaky(case_attrs)

        # Check for cross-run flaky (same test case + commit on CI with different status)
        {cross_run_flaky, historical_id} =
          check_cross_run_flaky(test_case_id, test.git_commit_sha, test.is_ci, status)

        is_flaky = is_flaky or cross_run_flaky

        # Collect historical run IDs that need to be marked as flaky
        ids_acc =
          if historical_id do
            [historical_id | ids_acc]
          else
            ids_acc
          end

        identity_key = {case_name, module_name, suite_name}
        {Map.put(data_acc, identity_key, %{status: status, is_flaky: is_flaky}), ids_acc}
      end)

    # Mark historical test case runs as flaky (insert updated versions)
    if Enum.any?(historical_flaky_ids) do
      mark_test_case_runs_as_flaky(historical_flaky_ids)
    end

    test_case_run_data
  end

  defp create_test_suites(test, module_id, test_suites, test_cases, test_case_run_data) do
    test_cases_by_suite =
      Enum.group_by(test_cases, fn case_attrs ->
        Map.get(case_attrs, :test_suite_name, "")
      end)

    {test_suite_runs, suite_name_to_id} =
      Enum.map_reduce(test_suites, %{}, fn suite_attrs, acc ->
        suite_id = UUIDv7.generate()
        suite_name = Map.get(suite_attrs, :name)

        suite_test_cases = Map.get(test_cases_by_suite, suite_name, [])
        test_case_count = length(suite_test_cases)

        avg_test_case_duration = calculate_avg_test_case_duration(suite_test_cases)

        # Get data for test cases in this suite
        suite_data =
          test_case_run_data
          |> Enum.filter(fn {{_name, _module, suite}, _data} -> suite == suite_name end)
          |> Enum.map(fn {_key, data} -> data end)

        suite_is_flaky = compute_aggregate_is_flaky(suite_data)

        suite_run = %{
          id: suite_id,
          name: suite_name,
          test_run_id: test.id,
          test_module_run_id: module_id,
          status: Map.get(suite_attrs, :status),
          is_flaky: suite_is_flaky,
          duration: Map.get(suite_attrs, :duration, 0),
          test_case_count: test_case_count,
          avg_test_case_duration: avg_test_case_duration,
          inserted_at: NaiveDateTime.utc_now()
        }

        updated_mapping = Map.put(acc, suite_name, suite_id)
        {suite_run, updated_mapping}
      end)

    IngestRepo.insert_all(TestSuiteRun, test_suite_runs)
    suite_name_to_id
  end

  defp create_test_cases_for_module(test, module_id, test_cases, suite_name_to_id, module_name, test_case_run_data) do
    # Build test case data with identity and latest run info
    test_case_data_list =
      test_cases
      |> Enum.map(fn case_attrs ->
        case_name = Map.get(case_attrs, :name)
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""
        identity_key = {case_name, module_name, suite_name}
        %{status: status, is_flaky: is_flaky} = Map.get(test_case_run_data, identity_key)

        %{
          name: case_name,
          module_name: module_name,
          suite_name: suite_name,
          status: status,
          # Only CI runs can mark a test_case as flaky; non-CI runs preserve existing status
          is_flaky: is_flaky and test.is_ci,
          duration: Map.get(case_attrs, :duration, 0),
          ran_at: test.ran_at
        }
      end)
      |> Enum.uniq_by(fn data -> {data.name, data.module_name, data.suite_name} end)

    # Create test cases (duplicates handled by ReplacingMergeTree)
    test_case_id_map = create_test_cases(test.project_id, test_case_data_list)

    {test_case_runs, all_failures, all_repetitions} =
      Enum.reduce(test_cases, {[], [], []}, fn case_attrs, {runs_acc, failures_acc, reps_acc} ->
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""

        test_suite_run_id = Map.get(suite_name_to_id, suite_name)

        test_case_run_id = UUIDv7.generate()

        # Lookup the test_case_id from our map
        case_name = Map.get(case_attrs, :name)
        identity_key = {case_name, module_name, suite_name}
        test_case_id = Map.get(test_case_id_map, identity_key)

        # Process repetitions if present
        repetitions = Map.get(case_attrs, :repetitions, [])

        # Use pre-computed status and is_flaky
        %{status: status, is_flaky: is_flaky} = Map.get(test_case_run_data, identity_key)

        test_case_run = %{
          id: test_case_run_id,
          name: case_name,
          test_run_id: test.id,
          test_module_run_id: module_id,
          test_suite_run_id: test_suite_run_id,
          test_case_id: test_case_id,
          project_id: test.project_id,
          is_ci: test.is_ci,
          scheme: test.scheme,
          account_id: test.account_id,
          ran_at: test.ran_at,
          git_branch: test.git_branch,
          git_commit_sha: test.git_commit_sha || "",
          status: status,
          is_flaky: is_flaky,
          duration: Map.get(case_attrs, :duration, 0),
          inserted_at: NaiveDateTime.utc_now(),
          module_name: module_name,
          suite_name: suite_name || ""
        }

        failures = Map.get(case_attrs, :failures, [])

        test_case_failures =
          Enum.map(failures, fn failure_attrs ->
            %{
              id: UUIDv7.generate(),
              test_case_run_id: test_case_run_id,
              message: Map.get(failure_attrs, :message),
              path: Map.get(failure_attrs, :path),
              line_number: Map.get(failure_attrs, :line_number),
              issue_type: Map.get(failure_attrs, :issue_type) || "unknown",
              inserted_at: NaiveDateTime.utc_now()
            }
          end)

        test_case_repetitions =
          Enum.map(repetitions, fn rep_attrs ->
            %{
              id: UUIDv7.generate(),
              test_case_run_id: test_case_run_id,
              repetition_number: Map.get(rep_attrs, :repetition_number),
              name: Map.get(rep_attrs, :name),
              status: Map.get(rep_attrs, :status),
              duration: Map.get(rep_attrs, :duration, 0),
              inserted_at: NaiveDateTime.utc_now()
            }
          end)

        {[test_case_run | runs_acc], test_case_failures ++ failures_acc, test_case_repetitions ++ reps_acc}
      end)

    IngestRepo.insert_all(TestCaseRun, test_case_runs)
    IngestRepo.insert_all(TestCaseFailure, all_failures)

    if Enum.any?(all_repetitions) do
      IngestRepo.insert_all(TestCaseRunRepetition, all_repetitions)
    end
  end

  defp calculate_avg_test_case_duration(test_cases) do
    test_case_count = length(test_cases)

    if test_case_count > 0 do
      total_duration =
        Enum.reduce(test_cases, 0, fn case_attrs, acc ->
          acc + Map.get(case_attrs, :duration, 0)
        end)

      round(total_duration / test_case_count)
    else
      0
    end
  end

  @doc """
  Lists test cases for a project directly from the test_cases table.
  Denormalized fields (last_status, last_duration, last_ran_at) are kept up to date
  by ReplacingMergeTree on each test run.
  """
  def list_test_cases(project_id, attrs) do
    two_weeks_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -14, :day)

    base_query =
      from(tc in TestCase,
        hints: ["FINAL"],
        where: tc.project_id == ^project_id,
        where: tc.last_ran_at >= ^two_weeks_ago
      )

    Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCase)
  end

  @doc """
  Lists test cases that are marked as flaky for a project.
  Queries test_cases where is_flaky = true and joins with test_case_runs for aggregated stats.
  """
  def list_flaky_test_cases(project_id, attrs) do
    page = Map.get(attrs, :page, 1)
    page_size = Map.get(attrs, :page_size, 20)
    order_by = attrs |> Map.get(:order_by, [:flaky_runs_count]) |> List.first()
    order_direction = attrs |> Map.get(:order_directions, [:desc]) |> List.first()
    filters = Map.get(attrs, :filters, [])

    search_filter =
      Enum.find(filters, fn f -> f[:field] == :name and f[:op] == :ilike_and end)

    search_term = if search_filter, do: "%#{search_filter[:value]}%"

    {order_clause, order_dir} =
      case {order_by, order_direction} do
        {:flaky_runs_count, :desc} -> {"flaky_runs_count", "DESC"}
        {:flaky_runs_count, :asc} -> {"flaky_runs_count", "ASC"}
        {:last_flaky_at, :desc} -> {"last_flaky_at", "DESC"}
        {:last_flaky_at, :asc} -> {"last_flaky_at", "ASC"}
        {:name, :desc} -> {"tc.name", "DESC"}
        {:name, :asc} -> {"tc.name", "ASC"}
        _ -> {"flaky_runs_count", "DESC"}
      end

    offset = (page - 1) * page_size

    base_where = "tc.project_id = {project_id:Int64} AND tc.is_flaky = true"

    where_clause =
      if search_term do
        "#{base_where} AND tc.name ILIKE {search_term:String}"
      else
        base_where
      end

    query = """
    SELECT
      tc.id,
      tc.name,
      tc.module_name,
      tc.suite_name,
      coalesce(stats.flaky_runs_count, 0) as flaky_runs_count,
      stats.last_flaky_at,
      stats.last_flaky_run_id
    FROM test_cases tc FINAL
    LEFT JOIN (
      SELECT
        test_case_id,
        count(*) as flaky_runs_count,
        max(inserted_at) as last_flaky_at,
        argMax(test_run_id, inserted_at) as last_flaky_run_id
      FROM test_case_runs
      WHERE project_id = {project_id:Int64} AND is_flaky = true
      GROUP BY test_case_id
    ) stats ON tc.id = stats.test_case_id
    WHERE #{where_clause}
    ORDER BY #{order_clause} #{order_dir}
    LIMIT {limit:Int64}
    OFFSET {offset:Int64}
    """

    count_query = """
    SELECT count(*) as count
    FROM test_cases FINAL
    WHERE project_id = {project_id:Int64} AND is_flaky = true
    #{if search_term, do: "AND name ILIKE {search_term:String}", else: ""}
    """

    params =
      if search_term do
        %{project_id: project_id, limit: page_size, offset: offset, search_term: search_term}
      else
        %{project_id: project_id, limit: page_size, offset: offset}
      end

    count_params =
      if search_term do
        %{project_id: project_id, search_term: search_term}
      else
        %{project_id: project_id}
      end

    {:ok, %{rows: rows}} = ClickHouseRepo.query(query, params)

    flaky_tests =
      Enum.map(rows, fn [id, name, module_name, suite_name, flaky_runs_count, last_flaky_at, last_flaky_run_id] ->
        uuid_string =
          case id do
            <<_::128>> = binary_uuid -> Ecto.UUID.load!(binary_uuid)
            string when is_binary(string) -> string
            nil -> nil
          end

        last_flaky_run_id_string =
          case last_flaky_run_id do
            <<_::128>> = binary_uuid -> Ecto.UUID.load!(binary_uuid)
            string when is_binary(string) -> string
            nil -> nil
          end

        %FlakyTestCase{
          id: uuid_string,
          name: name,
          module_name: module_name,
          suite_name: suite_name,
          flaky_runs_count: flaky_runs_count,
          last_flaky_at: last_flaky_at,
          last_flaky_run_id: last_flaky_run_id_string
        }
      end)

    {:ok, %{rows: [[total_count]]}} = ClickHouseRepo.query(count_query, count_params)
    total_pages = ceil(total_count / page_size)

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    }

    {flaky_tests, meta}
  end

  defp compute_test_case_run_status_and_flaky(case_attrs) do
    repetitions = Map.get(case_attrs, :repetitions, [])
    original_status = Map.get(case_attrs, :status)

    if Enum.any?(repetitions) do
      has_any_failure = Enum.any?(repetitions, fn rep -> Map.get(rep, :status) == "failure" end)

      if has_any_failure and original_status == "success" do
        # Test is flaky: had failures during repetitions but ultimately passed
        {original_status, true}
      else
        {original_status, false}
      end
    else
      {original_status, false}
    end
  end

  defp check_cross_run_flaky(test_case_id, git_commit_sha, is_ci, current_status)
       when is_ci and not is_nil(test_case_id) and not is_nil(git_commit_sha) and current_status in ["success", "failure"] do
    query =
      from(tcr in TestCaseRun,
        hints: ["FINAL"],
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.git_commit_sha == ^git_commit_sha,
        where: tcr.is_ci == true,
        where: tcr.status in ["success", "failure"],
        select: %{id: tcr.id, status: tcr.status},
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil ->
        {false, nil}

      %{id: existing_id, status: existing_status} when existing_status != current_status ->
        {true, existing_id}

      _ ->
        {false, nil}
    end
  end

  defp check_cross_run_flaky(_test_case_id, _git_commit_sha, _is_ci, _current_status) do
    {false, nil}
  end

  defp mark_test_case_runs_as_flaky(test_case_run_ids) when is_list(test_case_run_ids) do
    # Fetch existing test case runs
    query =
      from(tcr in TestCaseRun,
        hints: ["FINAL"],
        where: tcr.id in ^test_case_run_ids
      )

    existing_runs = ClickHouseRepo.all(query)

    # Insert updated versions with is_flaky = true
    updated_runs =
      Enum.map(existing_runs, fn run ->
        %{
          id: run.id,
          name: run.name,
          test_run_id: run.test_run_id,
          test_module_run_id: run.test_module_run_id,
          test_suite_run_id: run.test_suite_run_id,
          status: run.status,
          duration: run.duration,
          module_name: run.module_name,
          suite_name: run.suite_name,
          project_id: run.project_id,
          is_ci: run.is_ci,
          scheme: run.scheme,
          account_id: run.account_id,
          ran_at: run.ran_at,
          git_branch: run.git_branch,
          test_case_id: run.test_case_id,
          git_commit_sha: run.git_commit_sha,
          is_flaky: true,
          inserted_at: NaiveDateTime.utc_now()
        }
      end)

    if Enum.any?(updated_runs) do
      IngestRepo.insert_all(TestCaseRun, updated_runs)
    end

    :ok
  end

  defp compute_aggregate_is_flaky(test_case_run_data) do
    Enum.any?(test_case_run_data, fn %{is_flaky: is_flaky} -> is_flaky end)
  end

  @doc """
  Fetches flaky runs for a specific test case, grouped by scheme and commit SHA.
  Returns a list of groups, each containing runs with their failures.
  """
  def list_flaky_runs_for_test_case(test_case_id) do
    # Fetch all flaky test case runs for this test case
    flaky_runs_query =
      from(tcr in TestCaseRun,
        hints: ["FINAL"],
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at],
        limit: 100
      )

    flaky_runs = ClickHouseRepo.all(flaky_runs_query)

    if Enum.empty?(flaky_runs) do
      []
    else
      run_ids = Enum.map(flaky_runs, & &1.id)

      # Fetch failures and repetitions for all flaky runs
      failures = fetch_failures_for_runs(run_ids)
      failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

      repetitions = fetch_repetitions_for_runs(run_ids)
      repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

      # Group runs by scheme + commit_sha
      flaky_runs
      |> Enum.group_by(fn run -> {run.scheme, run.git_commit_sha} end)
      |> Enum.map(fn {{scheme, git_commit_sha}, runs} ->
        latest_ran_at = runs |> Enum.map(& &1.ran_at) |> Enum.max(NaiveDateTime)

        runs_with_details =
          Enum.map(runs, fn run ->
            run_failures = Map.get(failures_by_run_id, run.id, [])

            run_repetitions =
              repetitions_by_run_id
              |> Map.get(run.id, [])
              |> Enum.sort_by(& &1.repetition_number)

            run
            |> Map.put(:failures, run_failures)
            |> Map.put(:repetitions, run_repetitions)
          end)

        # Count passed/failed from repetitions if available, otherwise from run status
        {passed_count, failed_count} =
          Enum.reduce(runs_with_details, {0, 0}, fn run, {passed, failed} ->
            if Enum.any?(run.repetitions) do
              rep_passed = Enum.count(run.repetitions, &(&1.status == "success"))
              rep_failed = Enum.count(run.repetitions, &(&1.status == "failure"))
              {passed + rep_passed, failed + rep_failed}
            else
              case run.status do
                "success" -> {passed + 1, failed}
                "failure" -> {passed, failed + 1}
                _ -> {passed, failed}
              end
            end
          end)

        %{
          scheme: scheme,
          git_commit_sha: git_commit_sha,
          latest_ran_at: latest_ran_at,
          passed_count: passed_count,
          failed_count: failed_count,
          runs: runs_with_details
        }
      end)
      |> Enum.sort_by(& &1.latest_ran_at, {:desc, NaiveDateTime})
    end
  end

  @doc """
  Fetches flaky runs for a specific test run, grouped by test case name.
  Returns a list of groups, each containing runs with their failures.
  """
  def list_flaky_runs_for_test_run(test_run_id) do
    flaky_runs_query =
      from(tcr in TestCaseRun,
        hints: ["FINAL"],
        where: tcr.test_run_id == ^test_run_id,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at]
      )

    flaky_runs = ClickHouseRepo.all(flaky_runs_query)

    if Enum.empty?(flaky_runs) do
      []
    else
      run_ids = Enum.map(flaky_runs, & &1.id)

      failures = fetch_failures_for_runs(run_ids)
      failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

      repetitions = fetch_repetitions_for_runs(run_ids)
      repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

      flaky_runs
      |> Enum.group_by(fn run -> {run.test_case_id, run.name, run.module_name, run.suite_name} end)
      |> Enum.map(fn {{test_case_id, name, module_name, suite_name}, runs} ->
        latest_ran_at = runs |> Enum.map(& &1.ran_at) |> Enum.max(NaiveDateTime)

        runs_with_details =
          Enum.map(runs, fn run ->
            run_failures = Map.get(failures_by_run_id, run.id, [])

            run_repetitions =
              repetitions_by_run_id
              |> Map.get(run.id, [])
              |> Enum.sort_by(& &1.repetition_number)

            run
            |> Map.put(:failures, run_failures)
            |> Map.put(:repetitions, run_repetitions)
          end)

        {passed_count, failed_count} =
          Enum.reduce(runs_with_details, {0, 0}, fn run, {passed, failed} ->
            if Enum.any?(run.repetitions) do
              rep_passed = Enum.count(run.repetitions, &(&1.status == "success"))
              rep_failed = Enum.count(run.repetitions, &(&1.status == "failure"))
              {passed + rep_passed, failed + rep_failed}
            else
              case run.status do
                "success" -> {passed + 1, failed}
                "failure" -> {passed, failed + 1}
                _ -> {passed, failed}
              end
            end
          end)

        %{
          test_case_id: test_case_id,
          name: name,
          module_name: module_name,
          suite_name: suite_name,
          latest_ran_at: latest_ran_at,
          passed_count: passed_count,
          failed_count: failed_count,
          runs: runs_with_details
        }
      end)
      |> Enum.sort_by(& &1.latest_ran_at, {:desc, NaiveDateTime})
    end
  end

  defp fetch_failures_for_runs([]), do: []

  defp fetch_failures_for_runs(run_ids) do
    query =
      from(f in TestCaseFailure,
        where: f.test_case_run_id in ^run_ids,
        select: %{
          test_case_run_id: f.test_case_run_id,
          message: f.message,
          path: f.path,
          line_number: f.line_number,
          issue_type: f.issue_type
        }
      )

    ClickHouseRepo.all(query)
  end

  defp fetch_repetitions_for_runs([]), do: []

  defp fetch_repetitions_for_runs(run_ids) do
    query =
      from(r in TestCaseRunRepetition,
        where: r.test_case_run_id in ^run_ids,
        select: %{
          test_case_run_id: r.test_case_run_id,
          repetition_number: r.repetition_number,
          name: r.name,
          status: r.status,
          duration: r.duration
        }
      )

    ClickHouseRepo.all(query)
  end

  @doc """
  Clears stale flaky flags from test cases.

  A test case's is_flaky flag is considered stale if there have been no flaky
  test case runs for that test case in the last 14 days.

  Returns {:ok, count} where count is the number of test cases that had their
  is_flaky flag cleared.
  """
  def clear_stale_flaky_flags do
    fourteen_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -14, :day)

    # Query to get flaky test cases that have no recent flaky runs
    query = """
    SELECT
      tc.id,
      tc.name,
      tc.module_name,
      tc.suite_name,
      tc.project_id,
      tc.last_status,
      tc.last_duration,
      tc.last_ran_at,
      tc.inserted_at,
      tc.recent_durations,
      tc.avg_duration
    FROM test_cases tc FINAL
    LEFT JOIN (
      SELECT test_case_id
      FROM test_case_runs
      WHERE is_flaky = true AND inserted_at >= {cutoff:DateTime64(6)}
      GROUP BY test_case_id
    ) recent_flaky ON tc.id = recent_flaky.test_case_id
    WHERE tc.is_flaky = true AND recent_flaky.test_case_id IS NULL
    """

    {:ok, %{rows: rows}} = ClickHouseRepo.query(query, %{cutoff: fourteen_days_ago})

    if Enum.empty?(rows) do
      {:ok, 0}
    else
      now = NaiveDateTime.utc_now()

      test_cases_to_update =
        Enum.map(rows, fn [
                            id,
                            name,
                            module_name,
                            suite_name,
                            project_id,
                            last_status,
                            last_duration,
                            last_ran_at,
                            _inserted_at,
                            recent_durations,
                            avg_duration
                          ] ->
          uuid_string =
            case id do
              <<_::128>> = binary_uuid -> Ecto.UUID.load!(binary_uuid)
              string when is_binary(string) -> string
            end

          %{
            id: uuid_string,
            name: name,
            module_name: module_name,
            suite_name: suite_name,
            project_id: project_id,
            last_status: last_status,
            last_duration: last_duration,
            last_ran_at: last_ran_at,
            is_flaky: false,
            inserted_at: now,
            recent_durations: recent_durations,
            avg_duration: avg_duration
          }
        end)

      IngestRepo.insert_all(TestCase, test_cases_to_update)

      {:ok, length(test_cases_to_update)}
    end
  end
end
