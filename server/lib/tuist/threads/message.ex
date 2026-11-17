defmodule Tuist.Threads.Message do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_messages" do
    field :thread_id, :binary_id
    field :request_id, Ecto.UUID
    field :position, :integer
    field :kind, :string
    field :body, :string
    field :tool_name, :string
    field :tool_state, :string
    field :suggestions, {:array, :string}, default: []
    # A `card` message's NSH bundle and size class (`Tuist.Threads.Cards`).
    field :card_size, :string
    field :card_source, :string
    timestamps(type: :utc_datetime)
  end
end
