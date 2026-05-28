defmodule Tuist.Kura.UsageEvent do
  @moduledoc """
  ClickHouse schema for Kura usage rollups pushed by managed nodes.
  """
  use Ecto.Schema

  @primary_key false
  schema "kura_usage_events" do
    field :event_id, :string
    field :account_handle, :string
    field :project_handle, :string
    field :account_id, Ch, type: "Int64"
    field :project_id, Ch, type: "Int64"
    field :node_id, :string
    field :region, :string
    field :traffic_plane, :string
    field :direction, :string
    field :operation, :string
    field :protocol, :string
    field :artifact_kind, :string
    field :bytes, Ch, type: "UInt64"
    field :request_count, Ch, type: "UInt64"
    field :window_start, :naive_datetime
    field :window_seconds, Ch, type: "UInt32"
    field :inserted_at, :naive_datetime
  end
end
