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
  alias Tuist.Runs.Test
  alias Tuist.Runs.TestCase
  alias Tuist.Runs.TestCaseFailure
  alias Tuist.Runs.TestCaseRun
  alias Tuist.Runs.TestModuleRun
  alias Tuist.Runs.TestSuiteRun

  def valid_ci_providers, do: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

  def get_build(id) do
    Repo.get(Build, id)
  end

  def get_test(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    case ClickHouseRepo.get(Test, id) do
      nil -> {:error, :not_found}
      test -> {:ok, Repo.preload(test, preload)}
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
      cacheable_tasks_count: length(cacheable_tasks),
      cacheable_task_local_hits_count: Enum.count(cacheable_tasks, &(&1.status == :hit_local)),
      cacheable_task_remote_hits_count: Enum.count(cacheable_tasks, &(&1.status == :hit_remote))
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
    case %Test{}
         |> Test.create_changeset(attrs)
         |> IngestRepo.insert() do
      {:ok, test} ->
        create_test_modules(test, Map.get(attrs, :test_modules, []))

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

      test_cases =
        Enum.map(test_case_data_list, fn data ->
          %{
            id: generate_test_case_id(project_id, data.name, data.module_name, data.suite_name),
            name: data.name,
            module_name: data.module_name,
            suite_name: data.suite_name,
            project_id: project_id,
            last_status: data.status,
            last_duration: data.duration,
            last_ran_at: data.ran_at,
            inserted_at: now
          }
        end)

      IngestRepo.insert_all(TestCase, test_cases)

      Map.new(test_cases, fn tc ->
        {{tc.name, tc.module_name, tc.suite_name}, tc.id}
      end)
  end

  defp generate_test_case_id(project_id, name, module_name, suite_name) do
    identity = "#{project_id}:#{name}:#{module_name}:#{suite_name}"

    <<a::32, b::16, c::16, d::16, e::48>> =
      :crypto.hash(:md5, identity)
      |> binary_part(0, 16)

    # Format as UUID v4 (set version and variant bits)
    <<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>
    |> Ecto.UUID.cast!()
  end

  @doc """
  Gets a test case by its UUID with all denormalized fields.
  Returns nil if the test case is not found.
  """
  def get_test_case_by_id(id) do
    query =
      from(tc in TestCase,
        where: tc.id == ^id,
        select: %{
          id: tc.id,
          name: tc.name,
          module_name: tc.module_name,
          suite_name: tc.suite_name,
          project_id: tc.project_id,
          last_status: tc.last_status,
          last_duration: tc.last_duration,
          last_ran_at: tc.last_ran_at
        },
        limit: 1
      )

    ClickHouseRepo.one(query)
  end

  @doc """
  Lists test case runs for a specific test case by its UUID.
  Returns a tuple of {test_case_runs, meta} with pagination info.
  """
  def list_test_case_runs_by_test_case_id(test_case_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)
    search = Keyword.get(opts, :search, "")
    filters = Keyword.get(opts, :filters, [])
    sort_by = Keyword.get(opts, :sort_by, "ran_at")
    sort_order = Keyword.get(opts, :sort_order, "desc")

    offset = (page - 1) * page_size

    base_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id
      )

    base_query =
      if search == "" do
        base_query
      else
        search_term = "%#{search}%"
        where(base_query, [tcr], ilike(tcr.scheme, ^search_term))
      end

    base_query = apply_test_case_run_filters(base_query, filters)

    count_query = select(base_query, [tcr], count(tcr.id))
    total_count = ClickHouseRepo.one(count_query) || 0

    data_query =
      base_query
      |> apply_test_case_run_order(sort_by, sort_order)
      |> limit(^page_size)
      |> offset(^offset)
      |> select([tcr], %{
        id: tcr.id,
        status: tcr.status,
        duration: tcr.duration,
        inserted_at: tcr.inserted_at,
        test_run_id: tcr.test_run_id,
        scheme: tcr.scheme,
        is_ci: tcr.is_ci,
        account_id: tcr.account_id,
        ran_at: tcr.ran_at
      })

    test_case_runs =
      data_query
      |> ClickHouseRepo.all()
      |> Enum.map(fn row -> %{row | duration: normalize_duration(row.duration)} end)

    total_pages = if total_count > 0, do: ceil(total_count / page_size), else: 0

    meta = %{
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages,
      has_next_page?: page < total_pages,
      has_previous_page?: page > 1
    }

    {test_case_runs, meta}
  end

  defp create_test_modules(test, test_modules) do
    Enum.each(test_modules, fn module_attrs ->
      module_id = Ecto.UUID.generate()

      test_suites = Map.get(module_attrs, :test_suites, [])
      test_cases = Map.get(module_attrs, :test_cases, [])

      test_suite_count = length(test_suites)
      test_case_count = length(test_cases)

      avg_test_case_duration = calculate_avg_test_case_duration(test_cases)

      module_run_attrs = %{
        id: module_id,
        name: Map.get(module_attrs, :name),
        test_run_id: test.id,
        status: Map.get(module_attrs, :status),
        duration: Map.get(module_attrs, :duration, 0),
        test_suite_count: test_suite_count,
        test_case_count: test_case_count,
        avg_test_case_duration: avg_test_case_duration,
        inserted_at: NaiveDateTime.utc_now()
      }

      {:ok, _module_run} =
        %TestModuleRun{}
        |> TestModuleRun.create_changeset(module_run_attrs)
        |> IngestRepo.insert do
          suite_name_to_id = create_test_suites(test, module_id, test_suites, test_cases)

          create_test_cases_for_module(
            test,
            module_id,
            test_cases,
            suite_name_to_id,
            Map.get(module_attrs, :name)
          )
        end
    end)
  end

  defp create_test_suites(test, module_id, test_suites, test_cases) do
    test_cases_by_suite =
      Enum.group_by(test_cases, fn case_attrs ->
        Map.get(case_attrs, :test_suite_name, "")
      end)

    {test_suite_runs, suite_name_to_id} =
      Enum.map_reduce(test_suites, %{}, fn suite_attrs, acc ->
        suite_id = Ecto.UUID.generate()
        suite_name = Map.get(suite_attrs, :name)

        suite_test_cases = Map.get(test_cases_by_suite, suite_name, [])
        test_case_count = length(suite_test_cases)

        avg_test_case_duration = calculate_avg_test_case_duration(suite_test_cases)

        suite_run = %{
          id: suite_id,
          name: suite_name,
          test_run_id: test.id,
          test_module_run_id: module_id,
          status: Map.get(suite_attrs, :status),
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

  defp create_test_cases_for_module(test, module_id, test_cases, suite_name_to_id, module_name) do
    # Build test case data with identity and latest run info
    test_case_data_list =
      test_cases
      |> Enum.map(fn case_attrs ->
        %{
          name: Map.get(case_attrs, :name),
          module_name: module_name,
          suite_name: Map.get(case_attrs, :test_suite_name, "") || "",
          status: Map.get(case_attrs, :status),
          duration: Map.get(case_attrs, :duration, 0),
          ran_at: test.ran_at
        }
      end)
      |> Enum.uniq_by(fn data -> {data.name, data.module_name, data.suite_name} end)

    # Create test cases (duplicates handled by ReplacingMergeTree)
    test_case_id_map = create_test_cases(test.project_id, test_case_data_list)

    {test_case_runs, all_failures} =
      Enum.reduce(test_cases, {[], []}, fn case_attrs, {runs_acc, failures_acc} ->
        suite_name = Map.get(case_attrs, :test_suite_name, "")

        test_suite_run_id = Map.get(suite_name_to_id, suite_name)

        test_case_run_id = Ecto.UUID.generate()

        # Lookup the test_case_id from our map
        case_name = Map.get(case_attrs, :name)
        identity_key = {case_name, module_name, suite_name || ""}
        test_case_id = Map.get(test_case_id_map, identity_key)

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
          status: Map.get(case_attrs, :status),
          duration: Map.get(case_attrs, :duration, 0),
          inserted_at: NaiveDateTime.utc_now(),
          module_name: module_name,
          suite_name: suite_name || ""
        }

        failures = Map.get(case_attrs, :failures, [])

        test_case_failures =
          Enum.map(failures, fn failure_attrs ->
            %{
              id: Ecto.UUID.generate(),
              test_case_run_id: test_case_run_id,
              message: Map.get(failure_attrs, :message),
              path: Map.get(failure_attrs, :path),
              line_number: Map.get(failure_attrs, :line_number),
              issue_type: Map.get(failure_attrs, :issue_type) || "unknown",
              inserted_at: NaiveDateTime.utc_now()
            }
          end)

        {[test_case_run | runs_acc], test_case_failures ++ failures_acc}
      end)

    IngestRepo.insert_all(TestCaseRun, test_case_runs)
    IngestRepo.insert_all(TestCaseFailure, all_failures)
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

  ## Options
    * `:page` - Page number (default: 1)
    * `:page_size` - Number of items per page (default: 20)
    * `:sort_by` - Field to sort by: "name", "last_duration", "last_ran_at" (default: "last_ran_at")
    * `:sort_order` - Sort order: "asc" or "desc" (default: "desc")
    * `:filters` - List of filter maps with :field, :op, :value
    * `:search` - Search string to filter test cases by name (default: "")
  """
  def list_test_cases(project_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)
    sort_by = Keyword.get(opts, :sort_by, "last_ran_at")
    sort_order = Keyword.get(opts, :sort_order, "desc")
    filters = Keyword.get(opts, :filters, [])
    search = Keyword.get(opts, :search, "")

    offset = (page - 1) * page_size

    # Query test_cases directly with FINAL to force deduplication
    # Denormalized fields are kept up to date by ReplacingMergeTree
    base_query =
      from(tc in TestCase,
        hints: ["FINAL"],
        where: tc.project_id == ^project_id,
        select: %{
          id: tc.id,
          name: tc.name,
          module_name: tc.module_name,
          suite_name: tc.suite_name,
          last_duration: tc.last_duration,
          last_status: tc.last_status,
          last_ran_at: tc.last_ran_at
        }
      )

    # Apply filters
    base_query = apply_test_cases_filters(base_query, filters, search)

    # Apply sorting
    base_query = apply_test_cases_order(base_query, sort_by, sort_order)

    # Get count with FINAL for deduplication
    count_query = from(tc in TestCase, hints: ["FINAL"], where: tc.project_id == ^project_id, select: count())
    count_query = apply_test_cases_filters(count_query, filters, search)
    total_count = ClickHouseRepo.one(count_query) || 0

    # Get paginated data
    data_query =
      base_query
      |> limit(^page_size)
      |> offset(^offset)

    test_cases = ClickHouseRepo.all(data_query)

    total_pages = if total_count > 0, do: ceil(total_count / page_size), else: 0

    meta = %{
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages,
      has_next_page?: page < total_pages,
      has_previous_page?: page > 1
    }

    {test_cases, meta}
  end

  defp apply_test_cases_filters(query, filters, search) do
    query =
      if search != "" do
        search_term = "%#{search}%"
        where(query, [tc], ilike(tc.name, ^search_term))
      else
        query
      end

    Enum.reduce(filters, query, fn filter, acc ->
      field = Map.get(filter, :field)
      op = Map.get(filter, :op)
      value = Map.get(filter, :value)

      case {field, op} do
        {"module_name", :=~} ->
          search_term = "%#{value}%"
          where(acc, [tc], ilike(tc.module_name, ^search_term))

        {"suite_name", :=~} ->
          search_term = "%#{value}%"
          where(acc, [tc], ilike(tc.suite_name, ^search_term))

        {"name", :=~} ->
          search_term = "%#{value}%"
          where(acc, [tc], ilike(tc.name, ^search_term))

        {"last_status", :==} ->
          where(acc, [tc], tc.last_status == ^value)

        _ ->
          acc
      end
    end)
  end

  defp apply_test_cases_order(query, sort_by, sort_order) do
    direction = if sort_order == "asc", do: :asc, else: :desc

    case sort_by do
      "name" ->
        order_by(query, [tc], [{^direction, tc.name}])

      "last_duration" ->
        order_by(query, [tc], [{^direction, tc.last_duration}])

      # Support legacy "avg_duration" as alias for "last_duration"
      "avg_duration" ->
        order_by(query, [tc], [{^direction, tc.last_duration}])

      _ ->
        order_by(query, [tc], [{^direction, tc.last_ran_at}])
    end
  end

  defp normalize_duration(nil), do: 0
  defp normalize_duration(value) when is_float(value), do: round(value)
  defp normalize_duration(value) when is_integer(value), do: value
  defp normalize_duration(value), do: round(value * 1.0)

  defp apply_test_case_run_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc ->
      field = Map.get(filter, :field)
      op = Map.get(filter, :op)
      value = Map.get(filter, :value)

      case {field, op, value} do
        {"status", :==, status} when status in ["success", "failure", "skipped"] ->
          where(acc, [tcr], tcr.status == ^status)

        {"is_ci", :==, true} ->
          where(acc, [tcr], tcr.is_ci == true)

        {"account_id", :==, account_id} when is_integer(account_id) ->
          where(acc, [tcr], tcr.account_id == ^account_id)

        {"account_id", :==, account_id} when is_binary(account_id) ->
          case Integer.parse(account_id) do
            {id, _} -> where(acc, [tcr], tcr.account_id == ^id)
            :error -> acc
          end

        {"duration", :>, duration_str} when is_binary(duration_str) ->
          case Integer.parse(duration_str) do
            {duration_ms, _} -> where(acc, [tcr], tcr.duration > ^duration_ms)
            :error -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp apply_test_case_run_order(query, sort_by, sort_order) do
    direction = if sort_order == "asc", do: :asc, else: :desc

    case sort_by do
      "duration" -> order_by(query, [tcr], [{^direction, tcr.duration}])
      _ -> order_by(query, [tcr], [{^direction, tcr.ran_at}])
    end
  end
end
