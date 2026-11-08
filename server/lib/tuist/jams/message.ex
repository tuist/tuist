defmodule Tuist.Jams.Message do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "jam_messages" do
    field :jam_id, :binary_id
    field :request_id, Ecto.UUID
    field :position, :integer
    field :kind, :string
    field :body, :string
    field :tool_name, :string
    field :tool_state, :string
    field :suggestions, {:array, :string}, default: []
    timestamps(type: :utc_datetime)
  end
end
