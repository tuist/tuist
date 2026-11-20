defmodule LuftServer.Lounges.Member do
  @moduledoc "Direct membership and a person's monotonic read position."
  use Ecto.Schema

  @primary_key false
  schema "lounge_members" do
    field :lounge_id, :binary_id, primary_key: true
    field :user_id, :integer, primary_key: true
    field :last_read_position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
