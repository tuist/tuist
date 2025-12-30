defmodule Tuist.Cache.Entry do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "cas_entries" do
    field :id, Ch, type: "UUID"
    field :cas_id, Ch, type: "String"
    field :value, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :inserted_at, Ch, type: "DateTime"
  end
end
