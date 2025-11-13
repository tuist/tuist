defmodule Cache.Telemetry do
  @moduledoc """
  Telemetry handlers for CAS analytics events.
  """

  require Logger

  @doc """
  Attaches telemetry handlers for CAS events.
  """
  def attach do
    events = [
      [:cache, :cas, :download, :disk_hit],
      [:cache, :cas, :upload, :success]
    ]

    :telemetry.attach_many(
      "cache-analytics-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:cache, :cas, :download, :disk_hit], measurements, metadata, _config) do
    push_analytics_event("download", measurements, metadata)
  end

  defp handle_event([:cache, :cas, :upload, :success], measurements, metadata, _config) do
    push_analytics_event("upload", measurements, metadata)
  end

  defp push_analytics_event(action, measurements, metadata) do
    with {:ok, size} <- Map.fetch(measurements, :size),
         {:ok, cas_id} <- Map.fetch(metadata, :cas_id),
         {:ok, account_handle} <- Map.fetch(metadata, :account_handle),
         {:ok, project_handle} <- Map.fetch(metadata, :project_handle),
         {:ok, auth_header} <- Map.fetch(metadata, :auth_header) do
      event = %{
        action: action,
        size: size,
        cas_id: cas_id,
        account_handle: account_handle,
        project_handle: project_handle,
        auth_header: auth_header
      }

      Cache.AnalyticsPipeline.async_push(event)
    else
      :error ->
        Logger.debug(
          "Missing required metadata for CAS analytics: action=#{action}, measurements=#{inspect(measurements)}, metadata=#{inspect(metadata)}"
        )
    end
  end
end
