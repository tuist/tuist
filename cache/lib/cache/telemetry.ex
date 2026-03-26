defmodule Cache.Telemetry do
  @moduledoc """
  Telemetry handlers for Xcode cache and Gradle analytics events.
  """

  @doc """
  Attaches telemetry handlers for Xcode cache and Gradle events.
  """
  def attach do
    xcode_events = [
      [:cache, :xcode, :download, :disk_hit],
      [:cache, :xcode, :download, :s3_hit],
      [:cache, :xcode, :upload, :success]
    ]

    gradle_events = [
      [:cache, :gradle, :download, :disk_hit],
      [:cache, :gradle, :upload, :success]
    ]

    :telemetry.attach_many(
      "cache-analytics-handler",
      xcode_events ++ gradle_events,
      &Cache.Telemetry.handle_event/4,
      nil
    )
  end

  def handle_event([:cache, :xcode, :download, :disk_hit], measurements, metadata, _config) do
    push_xcode_event("download", measurements, metadata)
  end

  def handle_event([:cache, :xcode, :download, :s3_hit], measurements, metadata, _config) do
    push_xcode_event("download", measurements, metadata)
  end

  def handle_event([:cache, :xcode, :upload, :success], measurements, metadata, _config) do
    push_xcode_event("upload", measurements, metadata)
  end

  def handle_event([:cache, :gradle, :download, :disk_hit], measurements, metadata, _config) do
    push_gradle_event("download", measurements, metadata)
  end

  def handle_event([:cache, :gradle, :upload, :success], measurements, metadata, _config) do
    push_gradle_event("upload", measurements, metadata)
  end

  defp push_xcode_event(action, measurements, metadata) do
    event = %{
      action: action,
      size: measurements.size,
      cas_id: metadata.cas_id,
      account_handle: metadata.account_handle,
      project_handle: metadata.project_handle,
      is_ci: Map.get(metadata, :is_ci, false)
    }

    Cache.Xcode.EventsPipeline.async_push(event)
  end

  defp push_gradle_event(action, measurements, metadata) do
    event = %{
      action: action,
      size: measurements.size,
      cache_key: metadata.cache_key,
      account_handle: metadata.account_handle,
      project_handle: metadata.project_handle,
      is_ci: Map.get(metadata, :is_ci, false)
    }

    Cache.Gradle.EventsPipeline.async_push(event)
  end
end
