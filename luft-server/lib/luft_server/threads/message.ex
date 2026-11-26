defmodule LuftServer.Threads.Message do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_messages" do
    field :thread_id, :binary_id
    field :request_id, Ecto.UUID
    field :position, :integer
    field :kind, :string
    field :author_id, :integer
    # Human messages delegate the author's tools, never an arbitrary user session.
    field :author_session_id, :binary_id
    field :body, :string
    field :attachments, {:array, :map}, default: []
    field :tool_name, :string
    field :tool_state, :string
    field :suggestions, {:array, :string}, default: []
    field :suggestion_icons, :map, default: %{}
    field :card_size, :string
    field :card_source, :string
    field :decision, :map
    field :progress, :map
    # Set by the database from the thread's revision; see the migration.
    field :version, :integer, read_after_writes: true
    timestamps(type: :utc_datetime)
  end
end
