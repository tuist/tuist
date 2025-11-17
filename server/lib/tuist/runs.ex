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
  alias Tuist.Runs.TestCaseFailure
  alias Tuist.Runs.TestCaseRun
  alias Tuist.Runs.TestModuleRun
  alias Tuist.Runs.TestSuiteRun

  def get_build(id) do
    Repo.get(Build, id)
  end

  def get_test(id) do
    case IngestRepo.get(Test, id) do
      nil -> {:error, :not_found}
      test -> {:ok, test}
    end
  end

  def list_test_runs(attrs) do
    {results, meta} = Tuist.ClickHouseFlop.validate_and_run!(Test, attrs, for: Test)

    results = attach_user_account_names(results)

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
    {test_case_runs, meta} = Tuist.ClickHouseFlop.validate_and_run!(TestCaseRun, attrs, for: TestCaseRun)
    normalized_test_case_runs = Enum.map(test_case_runs, &TestCaseRun.normalize_enums/1)
    {normalized_test_case_runs, meta}
  end

  def list_test_case_failures(attrs) do
    Tuist.ClickHouseFlop.validate_and_run!(TestCaseFailure, attrs, for: TestCaseFailure)
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

  def list_test_run_failures(test_run_id, page, page_size) do
    query =
      from f in TestCaseFailure,
        join: tcr in TestCaseRun,
        on: f.test_case_run_id == tcr.id,
        where: tcr.test_run_id == ^test_run_id,
        order_by: [desc: f.inserted_at],
        limit: ^page_size,
        offset: ^((page - 1) * page_size),
        select: %{
          id: f.id,
          test_case_run_id: f.test_case_run_id,
          message: f.message,
          file_name: f.file_name,
          line_number: f.line_number,
          issue_type: f.issue_type,
          inserted_at: f.inserted_at,
          test_case_name: tcr.name,
          test_module_name: tcr.module_name,
          test_suite_name: tcr.suite_name
        }

    failures = ClickHouseRepo.all(query)
    total_count = get_test_run_failures_count(test_run_id)
    total_pages = ceil(total_count / page_size)

    meta = %{
      current_page: page,
      page_size: page_size,
      total_pages: total_pages,
      total_count: total_count
    }

    {failures, meta}
  end

  def list_test_suite_runs(attrs) do
    {test_suite_runs, meta} = Tuist.ClickHouseFlop.validate_and_run!(TestSuiteRun, attrs, for: TestSuiteRun)
    normalized_test_suite_runs = Enum.map(test_suite_runs, &TestSuiteRun.normalize_enums/1)
    {normalized_test_suite_runs, meta}
  end

  def list_test_module_runs(attrs) do
    {test_module_runs, meta} = Tuist.ClickHouseFlop.validate_and_run!(TestModuleRun, attrs, for: TestModuleRun)
    normalized_test_module_runs = Enum.map(test_module_runs, &TestModuleRun.normalize_enums/1)
    {normalized_test_module_runs, meta}
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
    case {build.ci_provider, build.ci_run_id, build.ci_project_handle} do
      {:github, run_id, project_handle} when not is_nil(run_id) and not is_nil(project_handle) ->
        "https://github.com/#{project_handle}/actions/runs/#{run_id}"

      {:gitlab, pipeline_id, project_path} when not is_nil(pipeline_id) and not is_nil(project_path) ->
        host = build.ci_host || "gitlab.com"
        "https://#{host}/#{project_path}/-/pipelines/#{pipeline_id}"

      {:bitrise, build_slug, _app_slug} when not is_nil(build_slug) ->
        "https://app.bitrise.io/build/#{build_slug}"

      {:circleci, build_num, project_handle} when not is_nil(build_num) and not is_nil(project_handle) ->
        "https://app.circleci.com/pipelines/github/#{project_handle}/#{build_num}"

      {:buildkite, build_number, project_handle} when not is_nil(build_number) and not is_nil(project_handle) ->
        "https://buildkite.com/#{project_handle}/builds/#{build_number}"

      {:codemagic, build_id, project_id} when not is_nil(build_id) and not is_nil(project_id) ->
        "https://codemagic.io/app/#{project_id}/build/#{build_id}"

      _ ->
        nil
    end
  end

  def create_test(attrs) do
    # Map status to raw enum value for ClickHouse
    attrs_with_mapped_status =
      case Map.get(attrs, :status) do
        :success -> Map.put(attrs, :status, 0)
        :failure -> Map.put(attrs, :status, 1)
        status when status in [0, 1] -> attrs
        # default to success
        _ -> Map.put(attrs, :status, 0)
      end

    case %Test{}
         |> Test.create_changeset(attrs_with_mapped_status)
         |> IngestRepo.insert() do
      {:ok, test} ->
        # Handle test modules, suites, and cases if present
        if Map.has_key?(attrs, :test_modules) and length(Map.get(attrs, :test_modules, [])) > 0 do
          create_test_modules(test, Map.get(attrs, :test_modules))
        end

        # Handle test cases if present (legacy support)
        if Map.has_key?(attrs, :test_cases) and length(Map.get(attrs, :test_cases, [])) > 0 do
          create_test_cases(test, Map.get(attrs, :test_cases))
        end

        # Load project with account from PostgreSQL for PubSub broadcast
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

  defp create_test_modules(test, test_modules) do
    Enum.each(test_modules, fn module_attrs ->
      # Map status to raw enum value for ClickHouse
      module_status =
        case Map.get(module_attrs, :status) do
          :success -> 0
          :failure -> 1
          status when status in [0, 1] -> status
          # default to success
          _ -> 0
        end

      module_id = Ecto.UUID.generate()

      # Get test suites and test cases
      test_suites = Map.get(module_attrs, :test_suites, [])
      test_cases = Map.get(module_attrs, :test_cases, [])

      # Compute statistics
      test_suite_count = length(test_suites)
      test_case_count = length(test_cases)

      avg_test_case_duration =
        if test_case_count > 0 do
          total_duration =
            Enum.reduce(test_cases, 0, fn case_attrs, acc ->
              acc + Map.get(case_attrs, :duration, 0)
            end)

          round(total_duration / test_case_count)
        else
          0
        end

      # Create test module run
      module_run_attrs = %{
        id: module_id,
        name: Map.get(module_attrs, :name),
        test_run_id: test.id,
        status: module_status,
        duration: Map.get(module_attrs, :duration, 0),
        test_suite_count: test_suite_count,
        test_case_count: test_case_count,
        avg_test_case_duration: avg_test_case_duration,
        inserted_at: NaiveDateTime.utc_now()
      }

      case %TestModuleRun{}
           |> TestModuleRun.create_changeset(module_run_attrs)
           |> IngestRepo.insert() do
        {:ok, _module_run} ->
          # Create test suites if present and get suite name to ID mapping
          suite_name_to_id =
            if Map.has_key?(module_attrs, :test_suites) do
              create_test_suites(test, module_id, test_suites, test_cases)
            else
              %{}
            end

          # Create test cases if present
          if Map.has_key?(module_attrs, :test_cases) do
            module_name = Map.get(module_attrs, :name)

            create_test_cases_for_module(
              test,
              module_id,
              test_cases,
              suite_name_to_id,
              module_name
            )
          end

        {:error, changeset} ->
          require Logger

          Logger.error("Failed to create test module run: #{inspect(changeset.errors)}")
      end
    end)
  end

  defp create_test_suites(test, module_id, test_suites, test_cases) do
    # Group test cases by suite name to compute statistics
    test_cases_by_suite =
      Enum.group_by(test_cases, fn case_attrs ->
        Map.get(case_attrs, :test_suite_name, "")
      end)

    {test_suite_runs, suite_name_to_id} =
      Enum.map_reduce(test_suites, %{}, fn suite_attrs, acc ->
        # Map status to raw enum value for ClickHouse
        suite_status =
          case Map.get(suite_attrs, :status) do
            :success -> 0
            :failure -> 1
            :skipped -> 2
            status when status in [0, 1, 2] -> status
            # default to success
            _ -> 0
          end

        suite_id = Ecto.UUID.generate()
        suite_name = Map.get(suite_attrs, :name)

        # Compute test case statistics for this suite
        suite_test_cases = Map.get(test_cases_by_suite, suite_name, [])
        test_case_count = length(suite_test_cases)

        avg_test_case_duration =
          if test_case_count > 0 do
            total_duration =
              Enum.reduce(suite_test_cases, 0, fn case_attrs, acc ->
                acc + Map.get(case_attrs, :duration, 0)
              end)

            round(total_duration / test_case_count)
          else
            0
          end

        suite_run = %{
          id: suite_id,
          name: suite_name,
          test_run_id: test.id,
          test_module_run_id: module_id,
          status: suite_status,
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
    now = NaiveDateTime.utc_now()

    # Create test case runs and collect failure data
    {test_case_runs, all_failures} =
      Enum.reduce(test_cases, {[], []}, fn case_attrs, {runs_acc, failures_acc} ->
        # Map status to raw enum value for ClickHouse
        case_status =
          case Map.get(case_attrs, :status) do
            :success -> 0
            :failure -> 1
            :skipped -> 2
            status when status in [0, 1, 2] -> status
            # default to success
            _ -> 0
          end

        # Try to find the test suite this test case belongs to
        # Match by test suite name within this specific module
        suite_name = Map.get(case_attrs, :test_suite_name, "")

        test_suite_run_id =
          case suite_name do
            "" -> nil
            nil -> nil
            suite_name -> Map.get(suite_name_to_id, suite_name)
          end

        test_case_run_id = Ecto.UUID.generate()

        test_case_run = %{
          id: test_case_run_id,
          name: Map.get(case_attrs, :name),
          test_run_id: test.id,
          test_module_run_id: module_id,
          test_suite_run_id: test_suite_run_id,
          status: case_status,
          duration: Map.get(case_attrs, :duration, 0),
          inserted_at: now,
          module_name: module_name,
          suite_name: suite_name || ""
        }

        # Process failures if present
        failures = Map.get(case_attrs, :failures, [])

        test_case_failures =
          Enum.map(failures, fn failure_attrs ->
            %{
              id: Ecto.UUID.generate(),
              test_case_run_id: test_case_run_id,
              message: Map.get(failure_attrs, :message),
              file_name: Map.get(failure_attrs, :file_name),
              line_number: Map.get(failure_attrs, :line_number),
              issue_type: Map.get(failure_attrs, :issue_type) || "unknown",
              inserted_at: now
            }
          end)

        {[test_case_run | runs_acc], test_case_failures ++ failures_acc}
      end)

    # Insert test case runs
    IngestRepo.insert_all(TestCaseRun, test_case_runs)

    # Insert test case failures if any
    if length(all_failures) > 0 do
      IngestRepo.insert_all(TestCaseFailure, all_failures)
    end
  end

  defp create_test_cases(_test, _test_cases) do
    # Legacy support for old API format - for now just log
    require Logger

    Logger.info("Legacy test_cases format received - consider using test_modules instead")
    :ok
  end

  defp attach_user_account_names(runs) do
    # Test runs use account_id instead of user_id
    # For now, we'll set user_account_name to nil since we don't have user info
    # This field will be populated by the command events if needed
    Enum.map(runs, fn run ->
      Map.put(run, :user_account_name, nil)
    end)
  end
end
