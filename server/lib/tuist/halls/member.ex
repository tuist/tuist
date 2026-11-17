defmodule Tuist.Halls.Member do
  @moduledoc """
  A person's place in a hall: who may read a direct conversation, and how far
  each person has read in any hall.
  """
  use Ecto.Schema

  @primary_key false
  schema "hall_members" do
    field :hall_id, :binary_id, primary_key: true
    field :user_id, :integer, primary_key: true
    field :last_read_position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
