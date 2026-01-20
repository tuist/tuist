defmodule Cache.Telemetry do
  @moduledoc """
  Telemetry handlers for cache analytics events.
  """

  require Logger

  @doc """
  Attaches telemetry handlers for cache events.
  """
  def attach do
    events = [
      [:cache, :cas, :download, :disk_hit],
      [:cache, :cas, :download, :s3_hit],
      [:cache, :cas, :upload, :success],
      [:cache, :module, :download, :disk_hit],
      [:cache, :module, :download, :s3_hit]
    ]

    :telemetry.attach_many(
      "cache-analytics-handler",
      events,
      &Cache.Telemetry.handle_event/4,
      nil
    )
  end

  def handle_event([:cache, :cas, :download, :disk_hit], measurements, metadata, _config) do
    push_cas_event("download", measurements, metadata)
  end

  def handle_event([:cache, :cas, :download, :s3_hit], measurements, metadata, _config) do
    push_cas_event("download", measurements, metadata)
  end

  def handle_event([:cache, :cas, :upload, :success], measurements, metadata, _config) do
    push_cas_event("upload", measurements, metadata)
  end

  def handle_event([:cache, :module, :download, :disk_hit], _measurements, metadata, _config) do
    push_module_cache_hit("disk", metadata)
  end

  def handle_event([:cache, :module, :download, :s3_hit], _measurements, metadata, _config) do
    push_module_cache_hit("s3", metadata)
  end

  defp push_cas_event(action, measurements, metadata) do
    event = %{
      action: action,
      size: measurements.size,
      cas_id: metadata.cas_id,
      account_handle: metadata.account_handle,
      project_handle: metadata.project_handle
    }

    Cache.CacheEventsPipeline.async_push(event)
  end

  defp push_module_cache_hit(source, metadata) do
    case normalize_run_id(Map.get(metadata, :run_id)) do
      nil ->
        Logger.error(
          "Missing run_id for module cache hit (source #{source}) " <>
            "account=#{metadata.account_handle} project=#{metadata.project_handle} " <>
            "remote_ip=#{inspect(Map.get(metadata, :remote_ip))}"
        )

      run_id ->
        event = %{
          event_type: "module_cache_hit",
          run_id: run_id,
          source: source,
          account_handle: metadata.account_handle,
          project_handle: metadata.project_handle
        }

        Cache.CacheEventsPipeline.async_push(event)
    end
  end

  defp normalize_run_id(nil), do: nil
  defp normalize_run_id(""), do: nil
  defp normalize_run_id(run_id), do: run_id
end
