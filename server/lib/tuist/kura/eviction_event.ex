defmodule Tuist.Kura.EvictionEvent do
  @moduledoc """
  ClickHouse schema for segment evictions Kura nodes shed under ring size
  pressure. `evicted_at - newest_content_at` is the shed age claim sizing is
  driven by: how soon after being written an artifact can be lost to size
  constraints.
  """
  use Ecto.Schema

  @primary_key false
  schema "kura_eviction_events" do
    field :event_id, :string
    field :account_id, Ch, type: "Int64"
    field :node_id, :string
    field :region, :string
    field :segment_id, :string
    field :reason, :string
    field :evicted_at, :naive_datetime
    field :segment_created_at, :naive_datetime
    field :newest_content_at, :naive_datetime
    field :artifact_count, Ch, type: "UInt64"
    field :bytes, Ch, type: "UInt64"
    field :inserted_at, :naive_datetime
  end
end
