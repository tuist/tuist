defmodule Tuist.API.Pipeline do
  @moduledoc ~S"""
  This module represents a Broadway data-processing pipeline for the API.
  Processing the data through a pipeline allows us to batch and process data efficiently.
  """
  use Broadway
  alias Broadway.Message

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: Tuist.API.Pipeline,
      producer: [
        module: {producer_module(), producer_options()},
        concurrency: 1
      ],
      processors: [default: [concurrency: 1]],
      batchers: [
        db: [concurrency: 1, batch_size: 100]
      ]
    )
  end

  defp producer_module() do
    Application.fetch_env!(:tuist, :api_pipeline_producer_module)
  end

  defp producer_options() do
    Application.fetch_env!(:tuist, :api_pipeline_producer_options)
  end

  def async_push(message) do
    if Tuist.Environment.test?() do
      :ok
    else
      buffer = producer_options() |> Keyword.fetch!(:buffer)
      OffBroadwayMemory.Buffer.push(buffer, message)
    end
  end

  @impl true
  def handle_message(_, %{data: {:cache_event, _}} = message, _) do
    message |> Message.put_batch_key(:cache_event) |> Message.put_batcher(:db)
  end

  @impl true
  def handle_batch(:db, cache_events, %{batch_key: :cache_event}, _) do
    events_count = length(cache_events)

    cache_events
    |> Enum.map(fn %{data: {:cache_event, cache_event}} ->
      cache_event
    end)
    |> Tuist.CommandEvents.create_cache_events()
    |> case do
      {^events_count, nil} -> cache_events
      _ -> Enum.map(cache_events, &Broadway.Message.failed(&1, :insert_all_error))
    end
  end
end
