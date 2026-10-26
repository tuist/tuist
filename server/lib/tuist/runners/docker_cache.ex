defmodule Tuist.Runners.DockerCache do
  @moduledoc """
  Reads behind the dashboard's Docker cache page. Each repository whose Linux
  jobs use Docker has one `docker` cache volume (`Tuist.Runners.CacheVolumes`)
  holding its jobs' Docker data root: the images and build cache they pulled
  and built. Its saved head carries the image inventory its job reported.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.JobSteps

  @step "Initialize containers"
  @sampled_jobs 2_000

  # A use reused saved data when its host restored some and its guest mounted
  # it, rather than formatting a data root it could not mount.
  defmacrop reused(usage) do
    quote do
      unquote(usage).warm == true and
        fragment("coalesce((?->>'reset')::boolean, false) = false", unquote(usage).docker_images)
    end
  end

  @doc """
  The account's Docker data roots, most recently used first, with what reusing
  each did during `period`.
  """
  def repositories(account_id, {_start, _finish} = period), do: repositories(account_id, nil, period)

  @doc "One repository's Docker data root and its images, or nil."
  def repository(account_id, volume_id, period) do
    case repositories(account_id, volume_id, period) do
      [repository] -> repository
      _ -> nil
    end
  end

  @doc """
  How the account's Docker data roots, or one, were reused during `period`:
  mounts and hit rate per hour or day, as for any cache volume, and the median
  Initialize containers step of the jobs that reused saved images and of those
  that started cold.
  """
  def analytics(account_id, volume_id, period) do
    %{
      activity: CacheVolumes.usage_analytics(account_id, volume_id, period, key: CacheVolumes.docker_key()),
      steps: steps(account_id, volume_id, period)
    }
  end

  defp repositories(account_id, volume_id, period) do
    query =
      from(v in Volume,
        left_join: head in Usage,
        on: head.id == v.head_id,
        where: v.account_id == ^account_id and v.key == ^CacheVolumes.docker_key(),
        order_by: [desc_nulls_last: v.last_used_at, asc: v.repository],
        select: {v, head}
      )

    query = if volume_id, do: from([v, _] in query, where: v.id == ^volume_id), else: query
    rows = Repo.all(query)
    stats = use_stats(Enum.map(rows, fn {volume, _} -> volume.id end), period)

    Enum.map(rows, fn {volume, head} ->
      images = images(head)
      %{uses: uses, hits: hits} = Map.get(stats, volume.id, %{uses: 0, hits: 0})

      %{
        id: volume.id,
        repository: volume.repository,
        provider: volume.provider,
        platform: volume.platform,
        architecture: volume.architecture,
        status: status(volume, head),
        images: images,
        image_count: length(images),
        saved_bytes: head && head.size_bytes,
        build_cache_bytes: head && head.docker_images && head.docker_images["build_cache_bytes"],
        last_saved_at: head && head.finished_at,
        last_used_at: volume.last_used_at,
        uses: uses,
        hits: hits,
        hit_rate: hit_rate(hits, uses)
      }
    end)
  end

  defp status(%Volume{deleted_at: %DateTime{}}, _head), do: :cleared
  defp status(_volume, %Usage{}), do: :ready
  defp status(_volume, nil), do: :waiting

  defp images(%Usage{docker_images: %{"images" => images}}) when is_list(images) do
    Enum.map(images, fn image ->
      references = image["references"] || []

      %{
        id: image["id"],
        reference: List.first(references) || String.slice(image["id"] || "", 0, 19),
        other_references: Enum.drop(references, 1),
        size_bytes: image["size_bytes"],
        last_used_at: parse_time(image["last_used_at"])
      }
    end)
  end

  defp images(_head), do: []

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp parse_time(_value), do: nil

  defp use_stats([], _period), do: %{}

  defp use_stats(volume_ids, {start, finish}) do
    from(u in Usage,
      where: u.volume_id in ^volume_ids and not is_nil(u.attached_at),
      where: u.attached_at >= ^start and u.attached_at <= ^finish,
      group_by: u.volume_id,
      select: {u.volume_id, %{uses: count(u.id), hits: filter(count(u.id), reused(u))}}
    )
    |> Repo.all()
    |> Map.new()
  end

  # The step medians overall and per bucket, over the period's most recent jobs.
  defp steps(account_id, volume_id, {start, finish}) do
    query =
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        where: v.account_id == ^account_id and v.key == ^CacheVolumes.docker_key(),
        where: not is_nil(u.attached_at) and u.attached_at >= ^start and u.attached_at <= ^finish,
        order_by: [desc: u.attached_at],
        limit: @sampled_jobs,
        select: %{job: u.workflow_job_id, at: u.attached_at, reused: reused(u)}
      )

    query = if volume_id, do: from([u, v] in query, where: v.id == ^volume_id), else: query
    uses = Repo.all(query)
    durations = JobSteps.durations_ms(account_id, uses |> Enum.map(& &1.job) |> Enum.uniq(), @step)
    timed = for use <- uses, ms = durations[use.job], do: Map.put(use, :ms, ms)
    Map.put(medians(timed), :points, step_points(timed, start, finish))
  end

  defp step_points(timed, start, finish) do
    seconds = if DateTime.diff(finish, start) <= 2 * 86_400, do: 3600, else: 86_400
    buckets = Enum.group_by(timed, &(div(DateTime.to_unix(&1.at), seconds) * seconds))
    first_bucket = div(DateTime.to_unix(start), seconds) * seconds
    last_bucket = div(DateTime.to_unix(finish), seconds) * seconds

    Enum.map(first_bucket..last_bucket//seconds, fn timestamp ->
      at = DateTime.from_unix!(timestamp)

      buckets
      |> Map.get(timestamp, [])
      |> medians()
      |> Map.put(:at, if(DateTime.before?(at, start), do: start, else: at))
    end)
  end

  defp medians(uses) do
    %{
      reused_ms: median(for(use <- uses, use.reused == true, do: use.ms)),
      cold_ms: median(for(use <- uses, use.reused != true, do: use.ms))
    }
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end

  defp hit_rate(_hits, 0), do: nil
  defp hit_rate(hits, uses), do: Float.round(100 * hits / uses, 1)
end
