defmodule Tuist.Kura.StorageSnapshot do
  @moduledoc """
  ClickHouse schema for periodic ring-occupancy snapshots from Kura nodes.
  The shrink half of claim sizing: occupancy that stays low for a long window
  means the claim is oversized, which evictions alone cannot show because an
  unfilled ring never evicts.
  """
  use Ecto.Schema

  @primary_key false
  schema "kura_storage_snapshots" do
    field :event_id, :string
    field :account_id, Ch, type: "Int64"
    field :node_id, :string
    field :region, :string
    field :captured_at, :naive_datetime
    field :ring_budget_bytes, Ch, type: "UInt64"
    field :desired_segment_count, Ch, type: "UInt64"
    field :live_segment_count, Ch, type: "UInt64"
    field :live_segment_bytes, Ch, type: "UInt64"
    field :oldest_segment_created_at, :naive_datetime
    field :newest_content_at, :naive_datetime
    field :inserted_at, :naive_datetime
  end
end
