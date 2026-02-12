defmodule Cache.Telemetry do
  @moduledoc """
  Telemetry handlers for CAS and Gradle analytics events.
  """

  @doc """
  Attaches telemetry handlers for CAS and Gradle events.
  """
  def attach do
    cas_events = [
      [:cache, :cas, :download, :disk_hit],
      [:cache, :cas, :download, :s3_hit],
      [:cache, :cas, :upload, :success]
    ]

    gradle_events = [
      [:cache, :gradle, :download, :disk_hit],
      [:cache, :gradle, :upload, :success]
    ]

    :telemetry.attach_many(
      "cache-analytics-handler",
      cas_events ++ gradle_events,
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

  def handle_event([:cache, :gradle, :download, :disk_hit], measurements, metadata, _config) do
    push_gradle_event("download", measurements, metadata)
  end

  def handle_event([:cache, :gradle, :upload, :success], measurements, metadata, _config) do
    push_gradle_event("upload", measurements, metadata)
  end

  defp push_cas_event(action, measurements, metadata) do
    event = %{
      action: action,
      size: measurements.size,
      cas_id: metadata.cas_id,
      account_handle: metadata.account_handle,
      project_handle: metadata.project_handle
    }

    Cache.CASEventsPipeline.async_push(event)
  end

  defp push_gradle_event(action, measurements, metadata) do
    event = %{
      action: action,
      size: measurements.size,
      cache_key: metadata.cache_key,
      account_handle: metadata.account_handle,
      project_handle: metadata.project_handle
    }

    Cache.GradleCacheEventsPipeline.async_push(event)
  end
end
