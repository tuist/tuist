defmodule Pulse.Storage.S3.RetentionCatchup do
  @moduledoc "Bounded, durable orphan catch-up outside the normal sliding sweep horizon."
  alias Pulse.ObjectStore
  alias Pulse.Storage.S3.ManifestOwner
  alias Pulse.Storage.S3.PagedManifest, as: Pages
  alias Pulse.Storage.S3.RetentionAdmission

  @day 86_400_000_000_000

  def new(from, through, width) do
    %{
      "from" => from,
      "through" => through,
      "day" => div(from, @day),
      "after" => nil,
      "bucket" => div(from, width) * width,
      "page_after" => nil,
      "data_done" => false,
      "metadata_done" => false,
      "dirty" => false
    }
  end

  def valid?(job, reclaimed, width) when is_map(job) do
    valid_range?(job, reclaimed) and valid_day?(job) and valid_bucket?(job, width) and
      Enum.all?(["data_done", "metadata_done", "dirty"], &is_boolean(job[&1])) and
      Enum.all?(["after", "page_after"], &(job[&1] == nil or (is_binary(job[&1]) and byte_size(job[&1]) <= 1024)))
  end

  def valid?(_, _, _), do: false

  defp valid_range?(job, reclaimed) do
    is_integer(job["from"]) and job["from"] >= 0 and is_integer(job["through"]) and
      job["from"] < job["through"] and job["through"] <= reclaimed
  end

  defp valid_day?(job) do
    is_integer(job["day"]) and job["day"] >= div(job["from"], @day) and job["day"] <= div(job["through"], @day) + 1
  end

  defp valid_bucket?(job, width) do
    is_integer(job["bucket"]) and rem(job["bucket"], width) == 0 and job["bucket"] >= div(job["from"], width) * width and
      job["bucket"] <= job["through"] + width
  end

  def step(root, tenant, signal, config) do
    job = root.paging["catchup"]
    {job, data_count} = data(job, tenant, signal, config)
    {job, page_count} = metadata(job, root, tenant, signal, config)

    job =
      if job["data_done"] and job["metadata_done"] do
        # Failed keys are not forgotten. Healthy ranges advance; retry complete
        # cycles until a cycle finishes without DELETE/admission failures.
        if job["dirty"], do: new(job["from"], job["through"], root.paging["width"])
      else
        job
      end

    {%{root | paging: Map.put(root.paging, "catchup", job)}, data_count + page_count}
  end

  defp data(%{"data_done" => true} = job, _, _, _), do: {job, 0}

  defp data(job, tenant, signal, config) do
    date = DateTime.from_unix!(job["day"] * @day, :nanosecond) |> DateTime.to_date() |> Date.to_iso8601()
    prefix = Pages.scope(tenant, signal) <> "date=#{date}/"
    {keys, next} = list!(config, prefix, job["after"])
    through = job["through"]

    expired = Enum.filter(keys, &expired_segment?(&1, through))
    {count, dirty} = delete_keys(expired, job["dirty"], config)

    day = if next, do: job["day"], else: job["day"] + 1

    {job
     |> Map.put("day", day)
     |> Map.put("after", next)
     |> Map.put("dirty", dirty)
     |> Map.put("data_done", day > div(job["through"], @day)), count}
  end

  defp metadata(%{"metadata_done" => true} = job, _, _, _, _), do: {job, 0}

  defp metadata(job, root, tenant, signal, config) do
    start = job["bucket"]
    width = root.paging["width"]

    if start + width > job["through"] do
      {Map.put(job, "metadata_done", true), 0}
    else
      if Enum.any?(root.paging["buckets"], &(&1["start"] == start)), do: Pages.fail(:invalid_manifest)
      prefix = Pages.scope(tenant, signal) <> "index/#{start}/"
      {keys, next} = list!(config, prefix, job["page_after"])

      {count, dirty} = delete_keys(keys, job["dirty"], config)

      following = if next, do: start, else: start + width

      {job
       |> Map.put("bucket", following)
       |> Map.put("page_after", next)
       |> Map.put("dirty", dirty)
       |> Map.put("metadata_done", following + width > job["through"]), count}
    end
  end

  defp expired_segment?(key, through) do
    case ManifestOwner.segment_from_key(key) do
      {:ok, s} -> s.max_ts < through
      :skip -> false
    end
  end

  # Deletes in order; any failed or unadmitted DELETE marks the cycle dirty.
  defp delete_keys(keys, dirty, config) do
    Enum.reduce(keys, {0, dirty}, fn key, {count, dirty} ->
      if delete(config, key), do: {count + 1, dirty}, else: {count, true}
    end)
  end

  defp list!(config, prefix, cursor) do
    case ObjectStore.list_page(config, prefix, cursor, min(128, Map.get(config, :retention_delete_limit, 512))) do
      {:ok, keys, next} -> {keys, next}
      {:error, reason} -> Pages.fail(reason)
    end
  end

  defp delete(config, key) do
    %{deadline: deadline} = Process.get(:pulse_metadata_budget)

    if System.monotonic_time(:millisecond) >= deadline do
      false
    else
      RetentionAdmission.delete(config, key) in [:ok, {:error, :not_found}]
    end
  end
end
