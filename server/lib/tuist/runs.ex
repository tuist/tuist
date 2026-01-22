defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.

    ## ClickHouse and deduplication

    This module uses ClickHouse with ReplacingMergeTree tables to store test data.
    ClickHouse doesn't support in-place updates - to "update" a row (e.g., setting `is_flaky`),
    we insert a new row with the updated values. ClickHouse eventually deduplicates rows with
    the same primary key by keeping the most recent one (based on `inserted_at`).

    However, until ClickHouse runs its background merge process, duplicate rows may exist.
    To ensure we always get the latest version of each row, we use one of these strategies:

    - For single-row queries: `ORDER BY inserted_at DESC LIMIT 1`
    - For multi-row queries: a subquery with `GROUP BY id` and `max(inserted_at)` to identify
      the latest version of each row, then join back to get the full row data
  """

  import Ecto.Query

  alias Tuist.Alerts.Workers.FlakyTestAlertWorker
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
        where: t.id == ^id,
        order_by: [desc: t.inserted_at],
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
        where: t.build_run_id == ^build_run_id,
        order_by: [desc: t.ran_at, desc: t.inserted_at],
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
        test_case_ids_with_flaky_run = create_test_modules(test, test_modules)

        project = Tuist.Projects.get_project_by_id(test.project_id)

        check_and_mark_flaky_test_cases(project, test_case_ids_with_flaky_run)

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

  defp check_and_mark_flaky_test_cases(_project, []), do: :ok

  defp check_and_mark_flaky_test_cases(%{auto_mark_flaky_tests: false}, _test_case_ids), do: :ok

  defp check_and_mark_flaky_test_cases(project, test_case_ids) do
    flaky_counts = get_flaky_runs_groups_counts_for_test_cases(test_case_ids)

    Enum.each(test_case_ids, fn test_case_id ->
      flaky_runs_count = Map.get(flaky_counts, test_case_id, 0)

      if flaky_runs_count >= project.auto_mark_flaky_threshold do
        {:ok, _} = update_test_case(test_case_id, %{is_flaky: true})

        auto_quarantined =
          if project.auto_quarantine_flaky_tests do
            {:ok, _} = update_test_case(test_case_id, %{is_quarantined: true})
            true
          else
            false
          end

        %{test_case_id: test_case_id, project_id: project.id, auto_quarantined: auto_quarantined, flaky_runs_count: flaky_runs_count}
        |> FlakyTestAlertWorker.new()
        |> Oban.insert!()
      end
    end)

    :ok
  end

  defp has_any_flaky_test_case?(test_modules) do
    test_modules
    |> Enum.flat_map(&Map.get(&1, :test_cases, []))
    |> Enum.any?(&test_case_is_flaky?/1)
  end

  defp test_case_is_flaky?(case_attrs) do
    repetitions = Map.get(case_attrs, :repetitions, [])
    statuses = Enum.map(repetitions, &Map.get(&1, :status))

    "success" in statuses and "failure" in statuses
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

    existing_data = get_project_test_cases(project_id, test_case_ids)

    # Track test cases that had a flaky run but aren't already marked as flaky
    {test_cases, test_cases_with_flaky_run} =
      Enum.map_reduce(test_case_ids_with_data, [], fn {id, data}, acc ->
        existing = Map.get(existing_data, id, %{recent_durations: []})
        new_durations = Enum.take([data.duration | existing.recent_durations], 50)

        new_avg =
          if Enum.empty?(new_durations),
            do: 0,
            else: div(Enum.sum(new_durations), length(new_durations))

        current_run_is_flaky = Map.get(data, :is_flaky, false)
        existing_is_flaky = Map.get(existing, :is_flaky, false)

        test_case = %{
          id: id,
          name: data.name,
          module_name: data.module_name,
          suite_name: data.suite_name,
          project_id: project_id,
          last_status: data.status,
          last_duration: data.duration,
          last_ran_at: data.ran_at,
          is_flaky: existing_is_flaky,
          inserted_at: now,
          recent_durations: new_durations,
          avg_duration: new_avg
        }

        acc = if current_run_is_flaky and not existing_is_flaky, do: [id | acc], else: acc
        {test_case, acc}
      end)

    IngestRepo.insert_all(TestCase, test_cases)

    test_case_id_map =
      Map.new(test_cases, fn tc ->
        {{tc.name, tc.module_name, tc.suite_name}, tc.id}
      end)

    {test_case_id_map, test_cases_with_flaky_run}
  end

  defp get_project_test_cases(_project_id, []), do: %{}

  defp get_project_test_cases(project_id, test_case_ids) do
    latest_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        where: test_case.id in ^test_case_ids,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    query =
      from(test_case in TestCase,
        join: latest in subquery(latest_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        select: %{
          id: test_case.id,
          recent_durations: test_case.recent_durations,
          is_flaky: test_case.is_flaky
        }
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
        where: tc.id == ^id,
        order_by: [desc: tc.inserted_at],
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      test_case -> {:ok, test_case}
    end
  end

  @doc """
  Updates a test case by inserting a new row with the given attributes.
  ClickHouse ReplacingMergeTree will keep the most recent row.

  Only `is_flaky` and `is_quarantined` are valid update attributes.
  """
  def update_test_case(test_case_id, update_attrs) when is_map(update_attrs) do
    valid_keys = [:is_flaky, :is_quarantined]
    filtered_attrs = Map.take(update_attrs, valid_keys)

    with {:ok, test_case} <- get_test_case_by_id(test_case_id) do
      attrs =
        test_case
        |> Map.from_struct()
        |> Map.delete(:__meta__)
        |> Map.merge(filtered_attrs)
        |> Map.put(:inserted_at, NaiveDateTime.utc_now())

      {1, nil} = IngestRepo.insert_all(TestCase, [attrs])

      {:ok, Map.merge(test_case, filtered_attrs)}
    end
  end


  @doc """
  Lists test case runs for a specific test case by its UUID.
  Returns a tuple of {test_case_runs, meta} with pagination info.
  """
  def list_test_case_runs_by_test_case_id(test_case_id, attrs) do
    base_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id
      )

    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(base_query, attrs, for: TestCaseRun)

    results = Repo.preload(results, :ran_by_account)

    {results, meta}
  end

  defp create_test_modules(test, test_modules) do
    test_case_run_data = get_test_case_run_data(test, test_modules)

    Enum.flat_map(test_modules, fn module_attrs ->
      module_id = UUIDv7.generate()
      module_name = Map.get(module_attrs, :name)

      test_suites = Map.get(module_attrs, :test_suites, [])
      test_cases = Map.get(module_attrs, :test_cases, [])

      test_suite_count = length(test_suites)
      test_case_count = length(test_cases)

      avg_test_case_duration = calculate_avg_test_case_duration(test_cases)

      module_test_case_run_data =
        test_case_run_data
        |> Enum.filter(fn {{_name, mod_name, _suite}, _data} -> mod_name == module_name end)
        |> Map.new()

      module_is_flaky = any_test_case_run_flaky?(Map.values(module_test_case_run_data))

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

      suite_name_to_id = create_test_suites(test, module_id, test_suites, test_cases, module_test_case_run_data)

      create_test_cases_for_module(
        test,
        module_id,
        test_cases,
        suite_name_to_id,
        module_name,
        module_test_case_run_data
      )
    end)
  end

  defp get_test_case_run_data(test, test_modules) do
    all_test_cases =
      Enum.flat_map(test_modules, fn module_attrs ->
        module_name = Map.get(module_attrs, :name)
        test_cases = Map.get(module_attrs, :test_cases, [])

        Enum.map(test_cases, fn case_attrs ->
          Map.put(case_attrs, :module_name, module_name)
        end)
      end)

    test_case_data =
      Enum.map(all_test_cases, fn case_attrs ->
        case_name = Map.get(case_attrs, :name)
        module_name = Map.get(case_attrs, :module_name)
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""
        test_case_id = generate_test_case_id(test.project_id, case_name, module_name, suite_name)

        %{
          identity_key: {case_name, module_name, suite_name},
          test_case_id: test_case_id,
          status: Map.get(case_attrs, :status),
          is_flaky: test_case_is_flaky?(case_attrs)
        }
      end)

    {test_case_data, historical_flaky_ids} =
      check_cross_run_flakiness(test, test_case_data)

    mark_test_case_runs_as_flaky(historical_flaky_ids)

    test_case_data = check_new_test_cases(test, test_case_data)

    Map.new(test_case_data, fn data ->
      {data.identity_key, %{status: data.status, is_flaky: data.is_flaky, is_new: data.is_new}}
    end)
  end

  defp check_cross_run_flakiness(%{is_ci: false}, test_case_data), do: {test_case_data, []}
  defp check_cross_run_flakiness(%{git_commit_sha: nil}, test_case_data), do: {test_case_data, []}

  defp check_cross_run_flakiness(test, test_case_data) do
    test_case_ids = Enum.map(test_case_data, & &1.test_case_id)
    existing_runs = get_existing_ci_runs_for_commit(test_case_ids, test.git_commit_sha)

    Enum.map_reduce(test_case_data, [], fn data, historical_ids ->
      case get_cross_run_flaky_ids(data, existing_runs) do
        [] ->
          {data, historical_ids}

        flaky_ids ->
          {%{data | is_flaky: true}, flaky_ids ++ historical_ids}
      end
    end)
  end

  defp get_cross_run_flaky_ids(data, existing_runs) do
    existing = Map.get(existing_runs, data.test_case_id, [])

    if data.status in ["success", "failure"] do
      existing
      |> Enum.filter(&(&1.status != data.status))
      |> Enum.map(& &1.id)
    else
      []
    end
  end

  defp get_existing_ci_runs_for_commit(test_case_ids, git_commit_sha) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id in ^test_case_ids,
        where: tcr.git_commit_sha == ^git_commit_sha,
        where: tcr.is_ci == true,
        where: tcr.status in ["success", "failure"],
        select: %{test_case_id: tcr.test_case_id, id: tcr.id, status: tcr.status}
      )

    query
    |> ClickHouseRepo.all()
    |> Enum.group_by(& &1.test_case_id)
  end

  defp check_new_test_cases(test, test_case_data) do
    project = Tuist.Projects.get_project_by_id(test.project_id)
    default_branch = project && project.default_branch

    if is_nil(default_branch) do
      Enum.map(test_case_data, &Map.put(&1, :is_new, false))
    else
      test_case_ids = Enum.map(test_case_data, & &1.test_case_id)
      existing_on_default_branch = get_test_case_ids_with_ci_runs_on_branch(test_case_ids, default_branch)

      Enum.map(test_case_data, fn data ->
        is_new = data.test_case_id not in existing_on_default_branch
        Map.put(data, :is_new, is_new)
      end)
    end
  end

  defp get_test_case_ids_with_ci_runs_on_branch(test_case_ids, branch) do
    ninety_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -90, :day)

    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id in ^test_case_ids,
        where: tcr.git_branch == ^branch,
        where: tcr.is_ci == true,
        where: tcr.ran_at >= ^ninety_days_ago,
        distinct: true,
        select: tcr.test_case_id
      )

    query
    |> ClickHouseRepo.all()
    |> MapSet.new()
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

        suite_data =
          test_case_run_data
          |> Enum.filter(fn {{_name, _module, suite}, _data} -> suite == suite_name end)
          |> Enum.map(fn {_key, data} -> data end)

        suite_is_flaky = any_test_case_run_flaky?(suite_data)

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
    {test_case_id_map, test_case_ids_with_flaky_run} = create_test_cases(test.project_id, test_case_data_list)

    {test_case_runs, all_failures, all_repetitions} =
      Enum.reduce(test_cases, {[], [], []}, fn case_attrs, {runs_acc, failures_acc, reps_acc} ->
        suite_name = Map.get(case_attrs, :test_suite_name, "") || ""

        test_suite_run_id = Map.get(suite_name_to_id, suite_name)

        test_case_run_id = UUIDv7.generate()

        # Lookup the test_case_id from our map
        case_name = Map.get(case_attrs, :name)
        identity_key = {case_name, module_name, suite_name}
        test_case_id = Map.get(test_case_id_map, identity_key)

        repetitions = Map.get(case_attrs, :repetitions, [])

        %{status: status, is_flaky: is_flaky, is_new: is_new} = Map.get(test_case_run_data, identity_key)

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
          is_new: is_new,
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

    test_case_ids_with_flaky_run
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

    latest_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        where: test_case.last_ran_at >= ^two_weeks_ago,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    base_query =
      from(test_case in TestCase,
        join: latest in subquery(latest_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at
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
    offset = (page - 1) * page_size

    search_term = extract_search_term(filters)

    results =
      project_id
      |> build_flaky_test_cases_query(search_term)
      |> apply_flaky_order(order_by, order_direction)
      |> from(limit: ^page_size, offset: ^offset)
      |> ClickHouseRepo.all()

    flaky_tests = Enum.map(results, &row_to_flaky_test_case/1)

    total_count =
      project_id
      |> build_flaky_test_cases_count_query(search_term)
      |> ClickHouseRepo.one()

    total_pages = if total_count > 0, do: ceil(total_count / page_size), else: 0

    meta = %{
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    }

    {flaky_tests, meta}
  end

  defp extract_search_term(filters) do
    search_filter = Enum.find(filters, fn f -> f[:field] == :name and f[:op] == :ilike_and end)
    if search_filter, do: search_filter[:value]
  end

  defp build_flaky_test_cases_query(project_id, search_term) do
    stats_subquery =
      from(test_case_run in TestCaseRun,
        where: test_case_run.project_id == ^project_id and test_case_run.is_flaky == true,
        group_by: test_case_run.test_case_id,
        select: %{
          test_case_id: test_case_run.test_case_id,
          flaky_runs_count: count(test_case_run.id),
          last_flaky_at: max(test_case_run.inserted_at),
          last_flaky_run_id: fragment("argMax(test_run_id, inserted_at)")
        }
      )

    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    base_query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        left_join: stats in subquery(stats_subquery),
        on: test_case.id == stats.test_case_id,
        where: test_case.is_flaky == true,
        select: %{
          id: test_case.id,
          name: test_case.name,
          module_name: test_case.module_name,
          suite_name: test_case.suite_name,
          flaky_runs_count: coalesce(stats.flaky_runs_count, 0),
          last_flaky_at: stats.last_flaky_at,
          last_flaky_run_id: stats.last_flaky_run_id
        }
      )

    apply_name_search(base_query, search_term)
  end

  defp build_flaky_test_cases_count_query(project_id, search_term) do
    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    base_query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        where: test_case.is_flaky == true,
        select: count(test_case.id)
      )

    apply_name_search(base_query, search_term)
  end

  defp apply_name_search(query, nil), do: query
  defp apply_name_search(query, term), do: from(q in query, where: ilike(q.name, ^"%#{term}%"))

  defp apply_flaky_order(query, :flaky_runs_count, :asc),
    do: from([tc, _latest, stats] in query, order_by: [asc: coalesce(stats.flaky_runs_count, 0)])

  defp apply_flaky_order(query, :last_flaky_at, :desc),
    do: from([tc, _latest, stats] in query, order_by: [desc: stats.last_flaky_at])

  defp apply_flaky_order(query, :last_flaky_at, :asc),
    do: from([tc, _latest, stats] in query, order_by: [asc: stats.last_flaky_at])

  defp apply_flaky_order(query, :name, :desc), do: from([tc, _latest, _stats] in query, order_by: [desc: tc.name])
  defp apply_flaky_order(query, :name, :asc), do: from([tc, _latest, _stats] in query, order_by: [asc: tc.name])

  defp apply_flaky_order(query, _, _),
    do: from([tc, _latest, stats] in query, order_by: [desc: coalesce(stats.flaky_runs_count, 0)])

  defp row_to_flaky_test_case(row) do
    %FlakyTestCase{
      id: row.id,
      name: row.name,
      module_name: row.module_name,
      suite_name: row.suite_name,
      flaky_runs_count: row.flaky_runs_count,
      last_flaky_at: row.last_flaky_at,
      last_flaky_run_id: row.last_flaky_run_id
    }
  end

  defp mark_test_case_runs_as_flaky(test_case_run_ids) when is_list(test_case_run_ids) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.id in ^test_case_run_ids
      )

    existing_runs = ClickHouseRepo.all(query)

    updated_runs =
      Enum.map(existing_runs, fn run ->
        run
        |> Map.from_struct()
        |> Map.drop([:__meta__, :ran_by_account])
        |> Map.merge(%{is_flaky: true, inserted_at: NaiveDateTime.utc_now()})
      end)

    if Enum.any?(updated_runs) do
      IngestRepo.insert_all(TestCaseRun, updated_runs)
    else
      :ok
    end
  end

  defp any_test_case_run_flaky?(test_case_run_data) do
    Enum.any?(test_case_run_data, fn %{is_flaky: is_flaky} -> is_flaky end)
  end

  @doc """
  Returns the count of unique flaky run groups (scheme + commit_sha) for a test case.
  """
  def get_flaky_runs_groups_count_for_test_case(test_case_id) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        select: fragment("count(DISTINCT (scheme, git_commit_sha))")
      )

    ClickHouseRepo.one(query) || 0
  end

  @doc """
  Returns a map of test_case_id => count of unique flaky run groups for multiple test cases.
  """
  def get_flaky_runs_groups_counts_for_test_cases([]), do: %{}

  def get_flaky_runs_groups_counts_for_test_cases(test_case_ids) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id in ^test_case_ids,
        where: tcr.is_flaky == true,
        group_by: tcr.test_case_id,
        select: {tcr.test_case_id, fragment("count(DISTINCT (scheme, git_commit_sha))")}
      )

    query
    |> ClickHouseRepo.all()
    |> Map.new()
  end

  @doc """
  Fetches flaky runs for a specific test case, grouped by scheme and commit SHA.
  Returns paginated groups, each containing all runs with their failures.
  """
  def list_flaky_runs_for_test_case(test_case_id, params \\ %{}) do
    page = Map.get(params, :page, 1)
    page_size = Map.get(params, :page_size, 20)
    offset = (page - 1) * page_size

    groups_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        group_by: [tcr.scheme, tcr.git_commit_sha],
        select: %{
          scheme: tcr.scheme,
          git_commit_sha: tcr.git_commit_sha,
          latest_ran_at: max(tcr.ran_at)
        },
        order_by: [desc: max(tcr.ran_at)],
        limit: ^page_size,
        offset: ^offset
      )

    groups = ClickHouseRepo.all(groups_query)
    group_keys = MapSet.new(groups, fn g -> {g.scheme, g.git_commit_sha} end)

    flaky_runs_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at]
      )

    flaky_runs =
      flaky_runs_query
      |> ClickHouseRepo.all()
      |> Enum.filter(fn run -> MapSet.member?(group_keys, {run.scheme, run.git_commit_sha}) end)

    run_ids = Enum.map(flaky_runs, & &1.id)

    failures = get_failures_for_runs(run_ids)
    failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

    repetitions = get_repetitions_for_runs(run_ids)
    repetitions_by_run_id = Enum.group_by(repetitions, & &1.test_case_run_id)

    runs_by_group = Enum.group_by(flaky_runs, fn run -> {run.scheme, run.git_commit_sha} end)

    flaky_groups =
      Enum.map(groups, fn group ->
        group_key = {group.scheme, group.git_commit_sha}
        runs = Map.get(runs_by_group, group_key, [])

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

        {passed_count, failed_count} = count_passed_failed(runs_with_details)

        %{
          scheme: group.scheme,
          git_commit_sha: group.git_commit_sha,
          latest_ran_at: group.latest_ran_at,
          passed_count: passed_count,
          failed_count: failed_count,
          runs: runs_with_details
        }
      end)

    total_count = get_flaky_runs_groups_count_for_test_case(test_case_id)

    meta = %{
      total_count: total_count,
      total_pages: if(total_count > 0, do: ceil(total_count / page_size), else: 0),
      current_page: page,
      page_size: page_size
    }

    {flaky_groups, meta}
  end

  defp count_passed_failed(runs_with_details) do
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
  end

  @doc """
  Gets flaky runs for a specific test run, grouped by test case name.
  Returns a list of groups, each containing runs with their failures.
  """
  def get_flaky_runs_for_test_run(test_run_id) do
    flaky_runs_query =
      from(tcr in TestCaseRun,
        where: tcr.test_run_id == ^test_run_id,
        where: tcr.is_flaky == true,
        order_by: [desc: tcr.ran_at]
      )

    flaky_runs = ClickHouseRepo.all(flaky_runs_query)

    run_ids = Enum.map(flaky_runs, & &1.id)

    failures = get_failures_for_runs(run_ids)
    failures_by_run_id = Enum.group_by(failures, & &1.test_case_run_id)

    repetitions = get_repetitions_for_runs(run_ids)
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

      {passed_count, failed_count} = count_passed_failed(runs_with_details)

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

  defp get_failures_for_runs([]), do: []

  defp get_failures_for_runs(run_ids) do
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

  defp get_repetitions_for_runs([]), do: []

  defp get_repetitions_for_runs(run_ids) do
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

    recent_flaky_subquery =
      from(test_case_run in TestCaseRun,
        where: test_case_run.is_flaky == true and test_case_run.inserted_at >= ^fourteen_days_ago,
        group_by: test_case_run.test_case_id,
        select: test_case_run.test_case_id
      )

    latest_test_case_subquery =
      from(test_case in TestCase,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        where: test_case.is_flaky == true,
        where: test_case.id not in subquery(recent_flaky_subquery)
      )

    stale_test_cases = ClickHouseRepo.all(query)
    now = NaiveDateTime.utc_now()

    test_cases_to_update =
      Enum.map(stale_test_cases, fn test_case ->
        test_case
        |> Map.from_struct()
        |> Map.delete(:__meta__)
        |> Map.merge(%{is_flaky: false, inserted_at: now})
      end)

    IngestRepo.insert_all(TestCase, test_cases_to_update)

    {:ok, length(test_cases_to_update)}
  end
end
