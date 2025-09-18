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
        db: [concurrency: 1, batch_size: 20, batch_timeout: to_timeout(second: 5)]
      ]
    )
  end

  defp producer_module do
    Application.fetch_env!(:tuist, :api_pipeline_producer_module)
  end

  defp producer_options do
    Application.fetch_env!(:tuist, :api_pipeline_producer_options)
  end

  def async_push(message) do
    if Tuist.Environment.test?() do
      :ok
    else
      buffer = Keyword.fetch!(producer_options(), :buffer)
      OffBroadwayMemory.Buffer.async_push(buffer, message)
    end
  end

  @impl true
  def handle_message(_, %{data: {event_name, %{project_id: project_id}}} = message, _) do
    message
    |> Message.put_batch_key({event_name, project_id})
    |> Message.put_batcher(:db)
  end

  @impl true
  def handle_batch(:db, cache_action_items, %{batch_key: {:create_cache_action_item, _}}, _) do
    # If we don't match against the inserted cache action items because in cases
    # where there's conflict, the cache action item is not inserted and therefore
    # not counted.
    {_, _} =
      cache_action_items
      |> Enum.map(fn %{data: {:create_cache_action_item, cache_action_item}} ->
        # Since we don't go through the changeset, the ID needs to be generated manually.
        Map.put(cache_action_item, :id, UUIDv7.generate())
      end)
      |> Tuist.CacheActionItems.create_cache_action_items()

    cache_action_items
  end
end
