defmodule LuftServer.Lounges.Lounge do
  @moduledoc "A public organization lounge or a private direct conversation."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "lounges" do
    field :account_id, :integer
    field :kind, Ecto.Enum, values: [:lounge, :direct]
    field :name, :string
    field :topic, :string
    field :direct_key, :string
    field :created_by_id, :integer
    field :request_id, Ecto.UUID
    field :last_position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
