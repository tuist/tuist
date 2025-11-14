defmodule Cache.Telemetry do
  @moduledoc """
  Telemetry handlers for CAS analytics events.
  """

  @doc """
  Attaches telemetry handlers for CAS events.
  """
  def attach do
    events = [
      [:cache, :cas, :download, :disk_hit],
      [:cache, :cas, :download, :s3_hit],
      [:cache, :cas, :upload, :success]
    ]

    :telemetry.attach_many(
      "cache-analytics-handler",
      events,
      &Cache.Telemetry.handle_event/4,
      nil
    )
  end

  def handle_event([:cache, :cas, :download, :disk_hit], measurements, metadata, _config) do
    push_analytics_event("download", measurements, metadata)
  end

  def handle_event([:cache, :cas, :download, :s3_hit], measurements, metadata, _config) do
    push_analytics_event("download", measurements, metadata)
  end

  def handle_event([:cache, :cas, :upload, :success], measurements, metadata, _config) do
    push_analytics_event("upload", measurements, metadata)
  end

  defp push_analytics_event(action, measurements, metadata) do
    event = %{
      action: action,
      size: measurements.size,
      cas_id: metadata.cas_id,
      account_handle: metadata.account_handle,
      project_handle: metadata.project_handle
    }

    Cache.CASEventsPipeline.async_push(event)
  end
end
