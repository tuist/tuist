defmodule Tuist.KeyValueStore.PromExPlugin do
  @moduledoc false
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_key_value_store_event_metrics,
        [
          counter(
            [:tuist, :key_value_store, :redis, :connected],
            event_name: [:redix, :connection],
            tags: [:connection_name, :address, :reconnection],
            description: "A connection with the Redis server has been established.",
            measurement: fn _ -> 1 end
          ),
          counter(
            [:tuist, :key_value_store, :redis, :disconnected],
            event_name: [:redix, :disconnection],
            tags: [:connection_name, :address, :reason],
            description: "A connection with the Redis server has been disconnected.",
            measurement: fn _ -> 1 end
          ),
          counter(
            [:tuist, :key_value_store, :redis, :failed_connecting],
            event_name: [:redix, :failed_connection],
            tags: [:connection_name, :address, :reason],
            description: "The app failed to connect to the Redis server.",
            measurement: fn _ -> 1 end
          ),
          counter(
            [:tuist, :key_value_store, :redis, :pipeline_completed],
            event_name: [:redix, :pipeline, :stop],
            tags: [:connection_name, :kind, :reason],
            description: "A pipeline has been completed.",
            measurement: fn _ -> 1 end
          )
        ]
      )
    ]
  end
end
