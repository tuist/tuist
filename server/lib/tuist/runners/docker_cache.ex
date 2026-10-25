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
  @sampled_jobs 500

  @doc """
  The account's Docker data roots, most recently used first, and what reusing
  them did during `period`.
  """
  def overview(account_id, {_start, _finish} = period) do
    repositories = repositories(account_id, nil, period)
    uses = uses(account_id, nil, period)

    %{
      repositories: repositories,
      saved_repositories: Enum.count(repositories, &(&1.status == :ready)),
      images: repositories |> Enum.map(& &1.image_count) |> Enum.sum(),
      saved_bytes: repositories |> Enum.map(&(&1.saved_bytes || 0)) |> Enum.sum(),
      activity: activity(account_id, uses)
    }
  end

  @doc "One repository's Docker data root, its images and its activity in `period`."
  def repository(account_id, volume_id, period) do
    case repositories(account_id, volume_id, period) do
      [repository] -> Map.put(repository, :activity, activity(account_id, uses(account_id, volume_id, period)))
      _ -> nil
    end
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
      select: {u.volume_id, %{uses: count(u.id), hits: filter(count(u.id), u.warm == true)}}
    )
    |> Repo.all()
    |> Map.new()
  end

  # The jobs that mounted a Docker data root in the period, newest first, with
  # whether they reused saved data.
  defp uses(account_id, volume_id, {start, finish}) do
    query =
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        where: v.account_id == ^account_id and v.key == ^CacheVolumes.docker_key(),
        where: not is_nil(u.attached_at) and u.attached_at >= ^start and u.attached_at <= ^finish,
        order_by: [desc: u.attached_at],
        limit: ^(2 * @sampled_jobs),
        select: {u.workflow_job_id, u.warm}
      )

    query = if volume_id, do: from([u, v] in query, where: v.id == ^volume_id), else: query
    Repo.all(query)
  end

  defp activity(account_id, uses) do
    hits = for {job, true} <- uses, do: job
    misses = for {job, warm} <- uses, warm != true, do: job

    %{
      uses: length(uses),
      hits: length(hits),
      hit_rate: hit_rate(length(hits), length(uses)),
      hit_step_ms: JobSteps.median_duration_ms(account_id, Enum.take(hits, @sampled_jobs), @step),
      miss_step_ms: JobSteps.median_duration_ms(account_id, Enum.take(misses, @sampled_jobs), @step)
    }
  end

  defp hit_rate(_hits, 0), do: nil
  defp hit_rate(hits, uses), do: Float.round(100 * hits / uses, 1)
end
