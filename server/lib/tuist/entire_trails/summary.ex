defmodule Tuist.EntireTrails.Summary do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "entire_trail_summaries" do
    belongs_to :connection, Tuist.EntireTrails.Connection
    field :trail_id, :string
    field :discussion_id, :string
    field :message_id, :string
    timestamps(type: :utc_datetime)
  end
end
