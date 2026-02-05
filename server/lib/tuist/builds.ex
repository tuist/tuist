defmodule Tuist.Builds do
  @moduledoc """
  Module for interacting with build runs.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Builds.Build
  alias Tuist.Builds.BuildFile
  alias Tuist.Builds.BuildIssue
  alias Tuist.Builds.BuildTarget
  alias Tuist.Builds.CacheableTask
  alias Tuist.Builds.CASOutput
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def valid_ci_providers, do: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

  def get_build(id) do
    query = from(b in Build, where: b.id == ^id, order_by: [desc: b.inserted_at], limit: 1)

    case ClickHouseRepo.one(query) do
      nil -> nil
      build -> Build.normalize_enums(build)
    end
  end

  def preload_postgres_associations(build, associations) do
    associations
    |> List.wrap()
    |> Enum.reduce(build, fn
      :project, acc ->
        project = Repo.get(Project, acc.project_id)
        %{acc | project: project}

      :ran_by_account, acc ->
        account =
          if acc.account_id do
            Repo.get(Account, acc.account_id)
          end

        %{acc | ran_by_account: account}

      {:project, nested_preloads}, acc ->
        project = Project |> Repo.get(acc.project_id) |> Repo.preload(nested_preloads)
        %{acc | project: project}

      _, acc ->
        acc
    end)
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

    build_data = Build.changeset(attrs)

    if Build.valid_status?(build_data.status) do
      {:ok, build_map} = Build.Buffer.insert(build_data)
      build = Build |> struct(build_map) |> Build.normalize_enums()

      Task.await_many(
        [
          Task.async(fn -> create_build_issues(build_map, Map.get(attrs, :issues, [])) end),
          Task.async(fn -> create_build_files(build_map, Map.get(attrs, :files, [])) end),
          Task.async(fn -> create_build_targets(build_map, Map.get(attrs, :targets, [])) end),
          Task.async(fn -> create_cacheable_tasks(build_map, cacheable_tasks) end),
          Task.async(fn -> create_cas_outputs(build_map, cas_outputs) end)
        ],
        30_000
      )

      project = Project |> Repo.get(build.project_id) |> Repo.preload(:account)

      if project do
        Tuist.PubSub.broadcast(
          build,
          "#{project.account.name}/#{project.name}",
          :build_created
        )
      end

      {:ok, build}
    else
      {:error, :invalid_build_status}
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
    ClickHouseFlop.validate_and_run!(BuildFile, attrs, for: BuildFile)
  end

  def list_build_targets(attrs) do
    ClickHouseFlop.validate_and_run!(BuildTarget, attrs, for: BuildTarget)
  end

  def list_cacheable_tasks(attrs) do
    ClickHouseFlop.validate_and_run!(CacheableTask, attrs, for: CacheableTask)
  end

  def list_cas_outputs(attrs) do
    ClickHouseFlop.validate_and_run!(CASOutput, attrs, for: CASOutput)
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
    custom_values = Keyword.get(opts, :custom_values)

    base_query = apply_custom_values_filter(Build, custom_values)

    {results, meta} = ClickHouseFlop.validate_and_run!(base_query, attrs, for: Build)

    results =
      results
      |> Enum.map(&Build.normalize_enums/1)
      |> maybe_preload_accounts(preload)

    {results, meta}
  end

  defp maybe_preload_accounts(builds, preload) when is_list(preload) do
    if :ran_by_account in preload or preload == [:ran_by_account] do
      preload_ran_by_accounts(builds)
    else
      builds
    end
  end

  defp maybe_preload_accounts(builds, :ran_by_account) do
    preload_ran_by_accounts(builds)
  end

  defp maybe_preload_accounts(builds, _), do: builds

  defp preload_ran_by_accounts(builds) do
    account_ids =
      builds
      |> Enum.map(& &1.account_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    accounts_map =
      if Enum.empty?(account_ids) do
        %{}
      else
        Account
        |> where([a], a.id in ^account_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
      end

    Enum.map(builds, fn build ->
      account = Map.get(accounts_map, build.account_id)
      %{build | ran_by_account: account}
    end)
  end

  def recent_build_status_counts(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)
    order_direction = if Keyword.get(opts, :order, :desc) == :desc, do: "DESC", else: "ASC"

    query = """
    SELECT
      countIf(status = 'success') as successful_count,
      countIf(status = 'failure') as failed_count
    FROM (
      SELECT status
      FROM build_runs
      WHERE project_id = {project_id:Int64}
      ORDER BY inserted_at #{order_direction}
      LIMIT {limit:UInt32}
    )
    """

    {:ok, %{rows: [[successful_count, failed_count]]}} =
      ClickHouseRepo.query(query, %{project_id: project_id, limit: limit})

    %{
      successful_count: successful_count,
      failed_count: failed_count
    }
  end

  def project_build_schemes(%Project{} = project) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    query = """
    SELECT DISTINCT scheme
    FROM build_runs
    WHERE project_id = {project_id:Int64}
      AND scheme IS NOT NULL
      AND inserted_at > {since:DateTime64(6)}
    """

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(query, %{project_id: project.id, since: thirty_days_ago})

    Enum.map(rows, fn [scheme] -> scheme end)
  end

  def project_build_configurations(%Project{} = project) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    query = """
    SELECT DISTINCT configuration
    FROM build_runs
    WHERE project_id = {project_id:Int64}
      AND configuration IS NOT NULL
      AND inserted_at > {since:DateTime64(6)}
    """

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(query, %{project_id: project.id, since: thirty_days_ago})

    Enum.map(rows, fn [configuration] -> configuration end)
  end

  def project_build_tags(%Project{} = project) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    query = """
    SELECT DISTINCT arrayJoin(custom_tags) as tag
    FROM build_runs
    WHERE project_id = {project_id:Int64}
      AND length(custom_tags) > 0
      AND inserted_at > {since:DateTime64(6)}
    ORDER BY tag
    """

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(query, %{project_id: project.id, since: thirty_days_ago})

    Enum.map(rows, fn [tag] -> tag end)
  end

  defp apply_custom_values_filter(query, nil), do: query
  defp apply_custom_values_filter(query, values_map) when values_map == %{}, do: query

  defp apply_custom_values_filter(query, values_map) when is_map(values_map) do
    Enum.reduce(values_map, query, fn {key, value}, q ->
      from(b in q, where: fragment("custom_values[?] = ?", ^key, ^value))
    end)
  end

  @doc """
  Constructs a CI run URL based on the CI provider and metadata.
  Returns nil if the build doesn't have complete CI information.
  """
  def build_ci_run_url(%Build{} = build) do
    Tuist.VCS.ci_run_url(build)
  end
end
