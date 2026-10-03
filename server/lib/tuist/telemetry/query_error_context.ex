defmodule Tuist.Telemetry.QueryErrorContext do
  @moduledoc """
  Keeps the most recent failed ClickHouse read in the calling process so the
  existing error report can include its query and timings without parameters.
  Successful queries clear the context, including successful retries.
  """

  @context_key {__MODULE__, :failed_query}
  @query_events [
    [:tuist, :click_house_repo, :query],
    [:tuist, :shadow_click_house_repo, :query],
    [:tuist, :ops_click_house_repo, :query]
  ]
  @statement_limit 16_384

  def attach do
    :telemetry.attach_many(__MODULE__, @query_events, &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, measurements, %{result: {:error, error}, query: query, repo: repo}, _config)
      when is_binary(query) do
    context = %{
      repository: inspect(repo),
      statement: String.slice(query, 0, @statement_limit),
      statement_truncated: String.length(query) > @statement_limit,
      parameters: "[REDACTED]",
      timings_ms: Map.new(measurements, fn {key, value} -> {key, milliseconds(value)} end)
    }

    Process.put(@context_key, {error, context})
    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    Process.delete(@context_key)
    :ok
  end

  def enrich_event(%Sentry.Event{original_exception: exception} = event) when not is_nil(exception) do
    case Process.get(@context_key) do
      {^exception, context} ->
        %{event | extra: Map.put(event.extra || %{}, :database_query, context)}

      _ ->
        event
    end
  end

  def enrich_event(event), do: event

  defp milliseconds(value) when is_integer(value), do: System.convert_time_unit(value, :native, :microsecond) / 1_000
  defp milliseconds(_value), do: nil
end
