defmodule LuftServer.Lounges.Message do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "lounge_messages" do
    field :lounge_id, :binary_id
    field :author_id, :integer
    field :request_id, Ecto.UUID
    field :position, :integer
    field :body, :string
    timestamps(type: :utc_datetime)
  end
end
