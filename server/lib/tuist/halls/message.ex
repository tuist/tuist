defmodule Tuist.Halls.Message do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "hall_messages" do
    field :hall_id, :binary_id
    field :author_id, :integer
    field :request_id, Ecto.UUID
    field :position, :integer
    field :body, :string
    timestamps(type: :utc_datetime)
  end
end
