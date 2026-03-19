defmodule TuistCommon.HTTP.TransportLogger do
  @moduledoc """
  Logs suspicious Bandit and Thousand Island transport events for incident correlation.
  """

  alias TuistCommon.HTTP.Transport

  require Logger

  @events [
    [:bandit, :request, :stop],
    [:bandit, :request, :exception],
    [:thousand_island, :connection, :stop],
    [:thousand_island, :connection, :recv_error],
    [:thousand_island, :connection, :send_error]
  ]

  def attach(handler_suffix \\ :default) do
    case :telemetry.attach_many(
           handler_id(handler_suffix),
           @events,
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def detach(handler_suffix \\ :default) do
    :telemetry.detach(handler_id(handler_suffix))
  end

  def handle_event([:bandit, :request, :stop], measurements, metadata, _config) do
    if Transport.bandit_request_timeout?(metadata) do
      Logger.warning(
        "Bandit request body read timed out",
        Map.to_list(Transport.bandit_timeout_log_metadata(measurements, metadata))
      )
    end
  end

  def handle_event([:bandit, :request, :exception], measurements, metadata, _config) do
    Logger.warning(
      "Bandit request raised an exception",
      Map.to_list(Transport.bandit_exception_log_metadata(measurements, metadata))
    )
  end

  def handle_event([:thousand_island, :connection, :stop], measurements, metadata, _config) do
    case Transport.thousand_island_connection_drop_reason(metadata) do
      nil ->
        :ok

      reason ->
        Logger.warning(
          "Thousand Island connection dropped",
          Map.to_list(Transport.thousand_island_drop_log_metadata(measurements, metadata, reason))
        )
    end
  end

  def handle_event([:thousand_island, :connection, event], measurements, metadata, _config)
      when event in [:recv_error, :send_error] do
    Logger.warning(
      "Thousand Island connection #{event}",
      Map.to_list(Transport.thousand_island_error_log_metadata(event, measurements, metadata))
    )
  end

  defp handler_id(handler_suffix), do: "#{__MODULE__}.#{handler_suffix}"
end
