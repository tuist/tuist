defmodule Cache.KeyValue.PromExPlugin do
  @moduledoc """
  PromEx plugin for KeyValue endpoints.

  Exposes counters and distributions for GET/PUT operations.
  """
  use PromEx.Plugin

  @entry_buckets [1, 2, 4, 8, 16, 32, 64, 128]

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_kv_event_metrics, [
      # GETs
      counter([:cache, :kv, :get, :total],
        event_name: [:cache, :kv, :get, :request],
        description: "Total KeyValue GET requests."
      ),
      counter([:cache, :kv, :get, :hit, :total],
        event_name: [:cache, :kv, :get, :hit],
        measurement: :count,
        description: "KeyValue GET hits."
      ),
      counter([:cache, :kv, :get, :miss, :total],
        event_name: [:cache, :kv, :get, :miss],
        description: "KeyValue GET misses."
      ),
      sum([:cache, :kv, :get, :bytes],
        event_name: [:cache, :kv, :get, :hit],
        measurement: :bytes,
        description: "Total bytes returned by KeyValue GET."
      ),
      distribution([:cache, :kv, :get, :payload_size, :bytes],
        event_name: [:cache, :kv, :get, :hit],
        measurement: :bytes,
        unit: :byte,
        description: "Distribution of KeyValue GET payload sizes.",
        reporter_options: [buckets: exponential!(256, 2, 18)]
      ),

      # PUTs
      counter([:cache, :kv, :put, :total],
        event_name: [:cache, :kv, :put, :request],
        description: "Total KeyValue PUT requests."
      ),
      counter([:cache, :kv, :put, :success, :total],
        event_name: [:cache, :kv, :put, :success],
        description: "Successful KeyValue PUT operations."
      ),
      counter([:cache, :kv, :put, :errors, :total],
        event_name: [:cache, :kv, :put, :error],
        description: "KeyValue PUT errors.",
        tags: [:reason],
        tag_values: fn md -> %{reason: to_string(Map.get(md, :reason, :unknown))} end
      ),
      sum([:cache, :kv, :put, :entries],
        event_name: [:cache, :kv, :put, :success],
        measurement: :entries_count,
        description: "Total entries stored via KeyValue PUT."
      ),
      distribution([:cache, :kv, :put, :entries, :distribution],
        event_name: [:cache, :kv, :put, :success],
        measurement: :entries_count,
        description: "Distribution of number of entries per KeyValue PUT.",
        reporter_options: [buckets: @entry_buckets]
      )
    ])
  end
end
