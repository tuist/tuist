defmodule Tuist.Runners.CacheVolumes.Query do
  @moduledoc "Account-scoped public volume data shared by HTTP, MCP and CLI clients."
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.Jobs

  @sorts ["volume", "repository", "used_space", "capacity", "last_used"]

  def run(:list, account_id, params) do
    with {:ok, page, size} <- pagination(params),
         {:ok, options} <- filters(params) do
      data = CacheVolumes.list(account_id, "", page, options ++ [page_size: size])

      {:ok,
       %{
         volumes: Enum.map(data.volumes, &volume(&1, Map.get(data.stats, &1.id, %{}))),
         pagination_metadata: metadata(page, size, CacheVolumes.count(account_id, "", options))
       }}
    end
  end

  def run(:show, account_id, params) do
    with {:ok, found} <- find(account_id, params) do
      {:ok, volume(found, Map.get(CacheVolumes.statistics([found.id]), found.id, %{}))}
    end
  end

  def run(:jobs, account_id, params) do
    with {:ok, found} <- find(account_id, params),
         {:ok, page, size} <- pagination(params) do
      {:ok,
       %{
         jobs: Enum.map(CacheVolumes.history(account_id, found.id, page, size), &usage/1),
         pagination_metadata: metadata(page, size, CacheVolumes.history_count(account_id, found.id))
       }}
    end
  end

  def run(:job_volumes, account_id, %{"workflow_job_id" => id}) do
    case Jobs.get_for_account(account_id, id) do
      {:ok, job} ->
        uses = CacheVolumes.for_job(account_id, job.workflow_run_id, job.workflow_job_id)
        stats = CacheVolumes.statistics(Enum.map(uses, & &1.volume_id))

        {:ok,
         %{
           volumes:
             Enum.map(uses, fn use ->
               %{volume: volume(use.volume, Map.get(stats, use.volume_id, %{})), usage: usage(use)}
             end)
         }}

      _ ->
        {:error, :not_found}
    end
  end

  def run(:clear, account_id, params) do
    with {:ok, found} <- find(account_id, params),
         {:ok, _} <- CacheVolumes.delete(account_id, found.id) do
      {:ok, %{id: found.id, cleared: true}}
    end
  end

  def run(:analytics, account_id, params) do
    with :ok <- optional_volume(account_id, params),
         {:ok, period} <- period(params) do
      {start, finish} = period
      id = params["volume_id"]
      duration = DateTime.diff(finish, start, :microsecond)
      previous = {DateTime.add(start, -duration, :microsecond), DateTime.add(start, -1, :microsecond)}
      storage = CacheVolumes.storage_history(account_id, period, id)
      activity = CacheVolumes.usage_analytics(account_id, id, period)
      previous_activity = CacheVolumes.usage_analytics(account_id, id, previous)

      {:ok,
       %{
         period: %{start: iso(start), end: iso(finish)},
         storage: Enum.map(storage, &Map.update!(&1, :at, fn at -> iso(at) end)),
         activity: activity(activity),
         previous_activity: activity(previous_activity),
         trends: %{
           volumes: storage_trend(storage, :volumes, period),
           used_bytes: storage_trend(storage, :used_bytes, period),
           hit_rate_percentage_points: difference(activity.hit_rate, previous_activity.hit_rate)
         }
       }}
    end
  end

  defp find(account_id, %{"volume_id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        case CacheVolumes.get(account_id, id) do
          nil -> {:error, :not_found}
          volume -> {:ok, volume}
        end

      :error ->
        {:error, :invalid_parameters}
    end
  end

  defp optional_volume(account_id, %{"volume_id" => _} = params) do
    with {:ok, _} <- find(account_id, params), do: :ok
  end

  defp optional_volume(_, _), do: :ok

  defp pagination(params) do
    page = Map.get(params, "page", 1)
    size = Map.get(params, "page_size", 20)

    if is_integer(page) and page in 1..100_000 and is_integer(size) and size in 1..100,
      do: {:ok, page, size},
      else: {:error, :invalid_parameters}
  end

  defp filters(params) do
    sort = Map.get(params, "sort_by", "last_used")
    order = Map.get(params, "sort_order", if(sort in ["volume", "repository"], do: "asc", else: "desc"))
    name = params["name"]
    repository = params["repository"]

    if sort in @sorts and order in ["asc", "desc"] and valid_filter?(name) and valid_filter?(repository),
      do: {:ok, [sort_by: sort, sort_order: order, name: name, repository: repository]},
      else: {:error, :invalid_parameters}
  end

  defp valid_filter?(nil), do: true
  defp valid_filter?(value), do: is_binary(value) and String.length(value) in 1..200

  defp period(params) do
    now = DateTime.utc_now()

    with {:ok, finish} <- datetime(Map.get(params, "end", now)),
         {:ok, start} <- datetime(Map.get(params, "start", DateTime.add(finish, -7, :day))),
         duration when duration > 0 and duration <= 90 * 86_400 <- DateTime.diff(finish, start),
         true <- DateTime.compare(finish, now) != :gt do
      {:ok, {start, finish}}
    else
      _ -> {:error, :invalid_parameters}
    end
  end

  defp datetime(%DateTime{} = value), do: {:ok, value}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, value, _} -> {:ok, value}
      _ -> {:error, :invalid_parameters}
    end
  end

  defp datetime(_), do: {:error, :invalid_parameters}

  defp volume(volume, stats) do
    used =
      if stats[:retained_copies] == 0 or
           (is_nil(volume.head_id) and is_nil(volume.deleted_at) and is_nil(stats[:retained_bytes])),
         do: 0,
         else: stats[:retained_bytes]

    capacity = if stats[:retained_copies] == 0, do: 0, else: stats[:retained_capacity_bytes]

    %{
      id: volume.id,
      key: volume.key,
      repository: volume.repository,
      provider: volume.provider,
      platform: volume.platform,
      architecture: volume.architecture,
      last_used_at: iso(volume.last_used_at),
      used_bytes: used,
      capacity_bytes: capacity,
      unmeasured_copies: stats[:unmeasured_copies] || 0,
      unmeasured_capacity_copies: stats[:unmeasured_capacity_copies] || 0
    }
  end

  defp usage(use) do
    {status, description} = status(use.status)

    %{
      id: use.id,
      workflow_job_id: use.workflow_job_id,
      workflow_run_id: use.workflow_run_id,
      job_name: use.job_name,
      workflow_name: use.workflow_name,
      cache_status: status,
      cache_status_description: description,
      cache_hit: use.warm,
      used_bytes: use.size_bytes,
      capacity_bytes: use.capacity_bytes,
      mounted_at: iso(use.attached_at)
    }
  end

  defp status("allocated"), do: {"preparing", "The volume is being prepared for this job."}
  defp status("attached"), do: {"attached", "The volume is mounted for this job. Changes have not been saved yet."}
  defp status("published"), do: {"saved", "Changes from this job were saved to the volume for future job runs."}
  defp status("discarded"), do: {"discarded", "Changes from this job were not saved for future job runs."}
  defp status(_), do: {"unknown", "The cache status is unavailable."}

  defp activity(data) do
    %{
      job_runs: data.uses,
      hit_rate: data.hit_rate,
      points: Enum.map(data.points, &%{at: iso(&1.at), job_runs: &1.uses, hit_rate: &1.hit_rate})
    }
  end

  defp storage_trend(points, metric, {start, finish}) do
    first = List.first(points)
    last = List.last(points)

    if first && last && DateTime.compare(first.at, start) == :eq && DateTime.compare(last.at, finish) == :eq do
      change = difference(last[metric], first[metric])
      %{change: change, percent: percent(change, first[metric])}
    else
      %{change: nil, percent: nil}
    end
  end

  defp difference(nil, _), do: nil
  defp difference(_, nil), do: nil
  defp difference(current, previous), do: current - previous
  defp percent(nil, _), do: nil
  defp percent(0, 0), do: 0
  defp percent(_, 0), do: nil
  defp percent(change, previous), do: change / previous * 100
  defp iso(nil), do: nil
  defp iso(value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp metadata(page, size, count) do
    %{
      current_page: page,
      page_size: size,
      total_count: count,
      total_pages: ceil(count / size),
      has_next_page: page * size < count,
      has_previous_page: page > 1
    }
  end
end
