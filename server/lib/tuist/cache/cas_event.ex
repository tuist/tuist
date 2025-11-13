defmodule Tuist.Cache.CASEvent do
  @moduledoc """
  Ecto schema for CAS events stored in ClickHouse.
  """
  use Ecto.Schema

  @primary_key false
  schema "cas_events" do
    field :id, Ch, type: "UUID"
    field :action, Ch, type: "Enum8('upload' = 0, 'download' = 1)"
    field :size, Ch, type: "Int64"
    field :cas_id, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :inserted_at, Ch, type: "DateTime"
  end
end
