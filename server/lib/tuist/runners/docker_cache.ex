defmodule Tuist.Runners.DockerCache do
  @moduledoc """
  Reads behind an image cache volume's Images tab and Initialize containers
  widget on the dashboard. Each repository whose Linux jobs use Docker has one
  `docker` cache volume (`Tuist.Runners.CacheVolumes`) holding its jobs' Docker
  data root: the images and build cache they pulled and built. Its saved head
  carries the image inventory its job reported.
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
  The images the volume's saved data root keeps, as the job that saved it
  reported them; none while nothing is saved or after the volume was cleared.
  """
  def images(account_id, volume_id) do
    from(v in Volume,
      join: head in Usage,
      on: head.id == v.head_id,
      where: v.account_id == ^account_id and v.id == ^volume_id and v.key == ^CacheVolumes.docker_key(),
      where: is_nil(v.deleted_at),
      select: head
    )
    |> Repo.one()
    |> inventory()
  end

  defp inventory(%Usage{docker_images: %{"images" => images}}) when is_list(images) do
    Enum.map(images, fn image ->
      references = image["references"] || []

      %{
        id: image["id"],
        name: image_name(references, image["id"]),
        size_bytes: image["size_bytes"],
        last_used_at: parse_time(image["last_used_at"])
      }
    end)
  end

  defp inventory(_head), do: []

  # An image shows as the first tag a job used for it, as its repository and
  # short digest when jobs pulled it only by digest, or as its short ID.
  defp image_name(references, id) do
    {digests, tags} = Enum.split_with(references, &String.contains?(&1, "@"))

    case {tags, digests} do
      {[tag | _], _} -> tag
      {[], [digest | _]} -> digest |> String.split("@sha256:", parts: 2) |> short_reference()
      _ -> String.slice(id || "", 0, 19)
    end
  end

  defp short_reference([name, hex]), do: name <> "@sha256:" <> String.slice(hex, 0, 12)
  defp short_reference([reference]), do: reference

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp parse_time(_value), do: nil

  @doc """
  The Initialize containers step (average, p50, p90 and p99) of the jobs that
  started from saved images and of those that started cold, over the period's
  most recent jobs, overall and per hour or day.
  """
  def steps(account_id, volume_id, {start, finish}) do
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
    {reused, cold} = Enum.split_with(timed, &(&1.reused == true))

    %{
      reused: stats(Enum.map(reused, & &1.ms)),
      cold: stats(Enum.map(cold, & &1.ms)),
      points: step_points(reused, start, finish)
    }
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
      |> Enum.map(& &1.ms)
      |> stats()
      |> Map.put(:at, if(DateTime.before?(at, start), do: start, else: at))
    end)
  end

  defp stats([]), do: %{avg: nil, p50: nil, p90: nil, p99: nil}

  defp stats(values) do
    sorted = Enum.sort(values)

    %{
      avg: round(Enum.sum(sorted) / length(sorted)),
      p50: percentile(sorted, 0.5),
      p90: percentile(sorted, 0.9),
      p99: percentile(sorted, 0.99)
    }
  end

  # Nearest-rank percentile of sorted values.
  defp percentile(sorted, p), do: Enum.at(sorted, max(ceil(p * length(sorted)) - 1, 0))
end
