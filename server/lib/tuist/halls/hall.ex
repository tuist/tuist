defmodule Tuist.Halls.Hall do
  @moduledoc """
  A long-lived conversation in an organization: a named hall every member can
  read, or a direct conversation between a few members.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "halls" do
    field :account_id, :integer
    field :kind, Ecto.Enum, values: [:hall, :direct]
    field :name, :string
    field :topic, :string
    field :direct_key, :string
    field :created_by_id, :integer
    field :request_id, Ecto.UUID
    field :last_position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
