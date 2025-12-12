defmodule Cache.DiskEvictionWorker do
  @moduledoc """
  Oban worker that evicts least-recently-used cache artifacts when local disk
  usage crosses the configured high watermark.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.CacheArtifacts
  alias Cache.Disk

  require Logger

  @batch_size 500

  @impl Oban.Worker
  def perform(_job) do
    storage_dir = Disk.storage_dir()

    case Disk.usage(storage_dir) do
      {:ok, stats} ->
        config = eviction_config()

        if stats.percent_used >= config.high_watermark do
          evict(storage_dir, stats, config)
        else
          :ok
        end

      {:error, reason} ->
        Logger.warning("Failed to inspect disk usage for eviction: #{inspect(reason)}")
        :ok
    end
  end

  defp eviction_config do
    cas_config = Application.get_env(:cache, :cas, [])

    high_watermark =
      cas_config
      |> Keyword.get(:disk_usage_high_watermark_percent, 85.0)
      |> max(0.0)

    target =
      cas_config
      |> Keyword.get(:disk_usage_target_percent, high_watermark * 0.85)
      |> max(0.0)

    target_percent =
      if target >= high_watermark do
        max(high_watermark - 5.0, 0.0)
      else
        target
      end

    %{
      high_watermark: high_watermark,
      target_percent: target_percent
    }
  end

  defp evict(storage_dir, stats, config) do
    do_evict(storage_dir, stats, config, stats.used_bytes, %{freed_bytes: 0, files: 0})
  end

  defp do_evict(storage_dir, stats, config, used_bytes, summary) do
    current_percent = percent_used(used_bytes, stats.total_bytes)

    if current_percent <= config.target_percent do
      log_summary(stats, config, used_bytes, summary)
    else
      batch = CacheArtifacts.oldest(@batch_size)

      if batch == [] do
        Logger.warning(
          "Disk usage #{format_percent(stats.percent_used)} exceeded #{format_percent(config.high_watermark)} but no CAS metadata entries were available for eviction"
        )

        :ok
      else
        {next_used_bytes, next_summary, removed} =
          process_batch(batch, stats, config, used_bytes, summary)

        if removed == 0 do
          Logger.info(
            "Eviction halted: unable to remove any artifacts despite usage at #{format_percent(current_percent)}"
          )

          :ok
        else
          do_evict(storage_dir, stats, config, next_used_bytes, next_summary)
        end
      end
    end
  end

  defp process_batch(batch, stats, config, used_bytes, summary) do
    {final_used, final_summary, _removed, keys_to_delete} =
      Enum.reduce_while(batch, {used_bytes, summary, 0, []}, fn entry, {acc_used, acc_summary, removed, keys} ->
        current_percent = percent_used(acc_used, stats.total_bytes)

        if current_percent <= config.target_percent do
          {:halt, {acc_used, acc_summary, removed, keys}}
        else
          {next_used, next_summary, removed_delta, key_to_delete} =
            handle_entry(entry, acc_used, acc_summary)

          next_keys = if key_to_delete, do: [key_to_delete | keys], else: keys
          {:cont, {next_used, next_summary, removed + removed_delta, next_keys}}
        end
      end)

    :ok = CacheArtifacts.delete_by_keys(keys_to_delete)

    {final_used, final_summary, length(keys_to_delete)}
  end

  defp handle_entry(entry, used_bytes, summary) do
    path = Disk.artifact_path(entry.key)
    size = entry.size_bytes || file_size(path) || 0

    case File.rm(path) do
      :ok ->
        {
          max(used_bytes - size, 0),
          %{summary | freed_bytes: summary.freed_bytes + size, files: summary.files + 1},
          1,
          entry.key
        }

      {:error, :enoent} ->
        {used_bytes, summary, 1, entry.key}

      {:error, reason} ->
        Logger.warning("Failed to evict #{entry.key}: #{inspect(reason)}")
        {used_bytes, summary, 0, nil}
    end
  end

  defp log_summary(stats, config, _final_used_bytes, %{files: 0}) do
    Logger.info(
      "Disk usage #{format_percent(stats.percent_used)} exceeded #{format_percent(config.high_watermark)}, but no artifacts could be evicted"
    )

    :ok
  end

  defp log_summary(stats, _config, final_used_bytes, %{freed_bytes: freed, files: count}) do
    final_percent = percent_used(final_used_bytes, stats.total_bytes)

    Logger.info(
      "Evicted #{count} artifacts freeing #{format_bytes(freed)}; disk usage #{format_percent(stats.percent_used)} -> #{format_percent(final_percent)}"
    )

    :ok
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> nil
    end
  end

  defp percent_used(_used, 0), do: 0.0
  defp percent_used(used, total), do: used / total * 100.0

  defp format_percent(value), do: "~.2f%" |> :io_lib.format([value]) |> to_string()

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
end
