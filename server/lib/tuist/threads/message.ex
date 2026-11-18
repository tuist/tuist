defmodule Tuist.Threads.Message do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_messages" do
    field :thread_id, :binary_id
    field :request_id, Ecto.UUID
    field :position, :integer
    field :kind, :string
    # The person who wrote a `human` message; nil for other kinds and for
    # messages from before authors were recorded, which are the owner's.
    field :author_id, :integer
    field :body, :string
    field :tool_name, :string
    field :tool_state, :string
    field :suggestions, {:array, :string}, default: []
    # A `card` message's NSH bundle and size class (`Tuist.Threads.Cards`).
    field :card_size, :string
    field :card_source, :string
    # A `progress` message's plan: `%{"steps" => [%{"title", "status"}]}`.
    # A running `tool` message's build or test progress instead: the last
    # snapshot of a Once run its command reported (`Threads.record_build_progress/3`).
    field :progress, :map
    timestamps(type: :utc_datetime)
  end
end
