defmodule Tuist.Gradle do
  @moduledoc """
  Context module for Gradle build analytics.

  All data is stored in ClickHouse for analytics purposes.
  """

  import Ecto.Query

  alias Tuist.Builds.Build, as: BuildRun
  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.Build
  alias Tuist.Gradle.CacheEvent
  alias Tuist.Gradle.Task
  alias Tuist.IngestRepo

  @doc """
  Creates a Gradle build with associated tasks.

  ## Parameters
    * `attrs` - Build attributes including:
      * `:project_id` - The project ID (required)
      * `:account_id` - The account ID (required)
      * `:duration_ms` - Build duration in milliseconds (required)
      * `:status` - Build status: "success", "failure", or "cancelled" (required)
      * `:gradle_version` - Gradle version (optional)
      * `:java_version` - Java version (optional)
      * `:is_ci` - Whether build ran in CI (optional, defaults to false)
      * `:git_branch` - Git branch name (optional)
      * `:git_commit_sha` - Git commit SHA (optional)
      * `:git_ref` - Git ref (optional)
      * `:custom_tags` - Build tags for filtering (optional)
      * `:custom_values` - Build metadata key-value pairs (optional)
      * `:tasks` - List of task attributes (optional)

  ## Returns
    * `{:ok, build_id}` on success
  """
  def create_build(attrs) do
    with :ok <- BuildRun.validate_custom_metadata(Map.get(attrs, :custom_tags, []), Map.get(attrs, :custom_values, %{})) do
      now = Map.get(attrs, :inserted_at) || NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      build_id = attrs.id
      tasks = Map.get(attrs, :tasks, [])

      task_counts = compute_task_counts(tasks)
      build_entry = build_entry(attrs, build_id, task_counts, now)

      Build.Buffer.insert(build_entry)

      if !Enum.empty?(tasks) do
        create_tasks(build_id, attrs.project_id, tasks, now)
      end

      machine_metrics = Map.get(attrs, :machine_metrics, [])

      create_machine_metrics(build_id, machine_metrics, now)

      {:ok, build_id}
    end
  end

  defp build_entry(attrs, build_id, task_counts, now) do
    %{
      id: build_id,
      project_id: attrs.project_id,
      account_id: attrs.account_id,
      duration_ms: attrs.duration_ms,
      gradle_version: Map.get(attrs, :gradle_version) || "",
      java_version: Map.get(attrs, :java_version) || "",
      is_ci: Map.get(attrs, :is_ci, false),
      status: attrs.status,
      git_branch: Map.get(attrs, :git_branch) || "",
      git_commit_sha: Map.get(attrs, :git_commit_sha) || "",
      git_ref: Map.get(attrs, :git_ref) || "",
      root_project_name: Map.get(attrs, :root_project_name) || "",
      tasks_local_hit_count: task_counts.local_hit,
      tasks_remote_hit_count: task_counts.remote_hit,
      tasks_up_to_date_count: task_counts.up_to_date,
      tasks_executed_count: task_counts.executed,
      tasks_failed_count: task_counts.failed,
      tasks_skipped_count: task_counts.skipped,
      tasks_no_source_count: task_counts.no_source,
      cacheable_tasks_count: task_counts.cacheable,
      requested_tasks: Map.get(attrs, :requested_tasks, []),
      custom_tags: Map.get(attrs, :custom_tags, []),
      custom_values: Map.get(attrs, :custom_values, %{}),
      inserted_at: now
    }
  end

  defp compute_task_counts(tasks) do
    Enum.reduce(
      tasks,
      %{local_hit: 0, remote_hit: 0, up_to_date: 0, executed: 0, failed: 0, skipped: 0, no_source: 0, cacheable: 0},
      fn task, acc ->
        outcome = to_string(task.outcome)
        cacheable = Map.get(task, :cacheable, false)

        acc
        |> Map.update!(String.to_existing_atom(outcome), &(&1 + 1))
        |> then(fn acc ->
          if cacheable && outcome != "up_to_date", do: Map.update!(acc, :cacheable, &(&1 + 1)), else: acc
        end)
      end
    )
  end

  defp create_machine_metrics(build_id, metrics, now) do
    entries =
      Enum.map(metrics, fn metric ->
        %{
          gradle_build_id: build_id,
          timestamp: metric.timestamp,
          cpu_usage_percent: metric.cpu_usage_percent / 1,
          memory_used_bytes: metric.memory_used_bytes,
          memory_total_bytes: metric.memory_total_bytes,
          network_bytes_in: metric.network_bytes_in,
          network_bytes_out: metric.network_bytes_out,
          disk_bytes_read: metric.disk_bytes_read,
          disk_bytes_written: metric.disk_bytes_written,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(BuildMachineMetric, entries)
  end

  defp create_tasks(build_id, project_id, tasks, now) do
    task_entries =
      Enum.map(tasks, fn task ->
        %{
          id: UUIDv7.generate(),
          gradle_build_id: build_id,
          task_path: task.task_path,
          task_type: Map.get(task, :task_type) || "",
          outcome: task.outcome,
          cacheable: Map.get(task, :cacheable, false),
          duration_ms: Map.get(task, :duration_ms, 0),
          cache_key: Map.get(task, :cache_key) || "",
          cache_artifact_size: Map.get(task, :cache_artifact_size),
          started_at: to_naive_datetime(Map.get(task, :started_at)),
          project_id: project_id,
          inserted_at: now
        }
      end)

    Enum.each(task_entries, &Task.Buffer.insert/1)
  end

  @doc """
  Gets a Gradle build by ID.
  """
  def get_build(id) do
    query =
      from(b in Build,
        where: b.id == ^id,
        limit: 1
      )

    case ClickHouseRepo.one(query) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end

  @doc """
  Lists Gradle builds for a project with Flop-based pagination.

  Returns `{builds, meta}` where `meta` contains pagination info.
  """
  def list_builds(project_id, flop_params \\ %{}, opts \\ []) do
    {custom_tag_filters, flop_params} = pop_custom_tag_filters(flop_params)

    base_query = from(b in Build, where: b.project_id == ^project_id)

    base_query =
      Enum.reduce(Keyword.get(opts, :requested_tasks_filters, []), base_query, fn
        {:has, value}, q ->
          from(b in q, where: fragment("has(?, ?)", b.requested_tasks, ^value))

        {:not_has, value}, q ->
          from(b in q, where: fragment("NOT has(?, ?)", b.requested_tasks, ^value))
      end)

    base_query = apply_custom_tag_filters(base_query, custom_tag_filters)

    ClickHouseFlop.validate_and_run!(base_query, flop_params, for: Build)
  end

  defp pop_custom_tag_filters(flop_params) do
    {filters, flop_params} = Map.pop(flop_params, :filters, [])
    {custom_tag_filters, filters} = Enum.split_with(filters, &custom_tag_filter?/1)

    {custom_tag_filters, Map.put(flop_params, :filters, filters)}
  end

  defp custom_tag_filter?(%{field: :custom_tags, op: op}) when op in [:contains, :not_contains], do: true

  defp custom_tag_filter?(_), do: false

  defp apply_custom_tag_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :contains, value: value}, q ->
        from(b in q, where: fragment("has(?, ?)", b.custom_tags, ^value))

      %{op: :not_contains, value: value}, q ->
        from(b in q, where: fragment("NOT has(?, ?)", b.custom_tags, ^value))
    end)
  end

  @doc """
  Lists the distinct Gradle build tags observed in a project during the last 30 days.
  """
  def project_build_tags(project) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    query = """
    SELECT DISTINCT arrayJoin(custom_tags) AS tag
    FROM gradle_builds
    WHERE project_id = {project_id:Int64}
      AND length(custom_tags) > 0
      AND inserted_at > {since:DateTime64(6)}
    ORDER BY tag
    LIMIT 1000
    """

    case ClickHouseRepo.query(query, %{project_id: project.id, since: thirty_days_ago}) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [tag] -> tag end)
      {:error, _reason} -> []
    end
  end

  @doc """
  Lists tasks for a specific Gradle build.
  """
  def list_tasks(build_id) do
    query =
      from(t in Task,
        where: t.gradle_build_id == ^build_id,
        order_by: [asc: t.task_path]
      )

    ClickHouseRepo.all(query)
  end

  @doc """
  Lists tasks for a specific Gradle build with Flop-based pagination.

  Returns `{tasks, meta}` where `meta` contains pagination info.
  """
  def list_tasks(build_id, flop_params) do
    base_query = from(t in Task, where: t.gradle_build_id == ^build_id)
    ClickHouseFlop.validate_and_run!(base_query, flop_params, for: Task)
  end

  @doc """
  Returns the earliest task started_at time for a build.

  Used as the reference point for computing "started after" offsets.
  """
  def build_started_at(build_id) do
    query =
      from(t in Task,
        where: t.gradle_build_id == ^build_id and not is_nil(t.started_at),
        select: min(t.started_at)
      )

    ClickHouseRepo.one(query)
  end

  @doc """
  Returns aggregate cache metrics for a build's tasks.

  Used for cache summary widgets (download/upload bytes, throughput).
  """
  def task_cache_aggregates(build_id) do
    query =
      from(t in Task,
        where: t.gradle_build_id == ^build_id and t.cacheable == true,
        select: %{
          cache_download_bytes:
            coalesce(
              sum(fragment("if(? = 'remote_hit', coalesce(?, 0), 0)", t.outcome, t.cache_artifact_size)),
              0
            ),
          cache_upload_bytes:
            coalesce(
              sum(fragment("if(? = 'executed', coalesce(?, 0), 0)", t.outcome, t.cache_artifact_size)),
              0
            ),
          download_duration_ms:
            coalesce(
              sum(
                fragment(
                  "if(? = 'remote_hit' AND ? IS NOT NULL, ?, 0)",
                  t.outcome,
                  t.cache_artifact_size,
                  t.duration_ms
                )
              ),
              0
            ),
          upload_duration_ms:
            coalesce(
              sum(
                fragment(
                  "if(? = 'executed' AND ? IS NOT NULL, ?, 0)",
                  t.outcome,
                  t.cache_artifact_size,
                  t.duration_ms
                )
              ),
              0
            )
        }
      )

    ClickHouseRepo.one(query)
  end

  @doc """
  Creates multiple Gradle cache events in a batch.

  ## Parameters
    * `events` - List of event attributes including:
      * `:action` - "upload" or "download"
      * `:cache_key` - The cache key
      * `:size` - Size in bytes
      * `:duration_ms` - Duration in milliseconds (optional)
      * `:is_hit` - Whether it was a cache hit (optional, defaults to true)
      * `:is_ci` - Whether it happened in CI (optional, defaults to false)
      * `:gradle_build_id` - The associated build ID (optional)
      * `:project_id` - The project ID
      * `:account_handle` - The account handle
      * `:project_handle` - The project handle
  """
  def create_cache_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          action: event.action,
          cache_key: event.cache_key,
          size: event.size,
          duration_ms: Map.get(event, :duration_ms, 0),
          is_hit: Map.get(event, :is_hit, true),
          is_ci: Map.get(event, :is_ci, false),
          gradle_build_id: Map.get(event, :gradle_build_id),
          project_id: event.project_id,
          account_handle: event.account_handle,
          project_handle: event.project_handle,
          cache_endpoint: event.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(CacheEvent, entries)
  end

  @doc """
  Calculates the cache hit rate for a build as a percentage.

  Returns `nil` if there are no cacheable tasks that were either
  cache hits or executed.
  """
  def cache_hit_rate(build) do
    from_cache = (build.tasks_local_hit_count || 0) + (build.tasks_remote_hit_count || 0)
    total = build.cacheable_tasks_count || 0

    if total > 0 do
      Float.round(from_cache / total * 100.0, 1)
    end
  end

  defp to_naive_datetime(nil), do: nil

  defp to_naive_datetime(%DateTime{} = dt), do: dt |> DateTime.to_naive() |> ensure_usec_precision()

  defp to_naive_datetime(%NaiveDateTime{} = ndt), do: ensure_usec_precision(ndt)

  defp ensure_usec_precision(%NaiveDateTime{microsecond: {usec, _}} = ndt), do: %{ndt | microsecond: {usec, 6}}
end
