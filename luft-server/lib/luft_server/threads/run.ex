defmodule LuftServer.Threads.Run do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_runs" do
    field :thread_id, :binary_id
    field :message_id, :binary_id
    field :approval_id, :binary_id
    field :kind, :string, default: "inference"
    field :status, :string, default: "queued"
    field :attempt, :integer, default: 0
    field :session_id, Ecto.UUID
    field :heartbeat_at, :utc_datetime
    field :waited_seconds, :integer, default: 0
    field :checkpoint, LuftServer.Threads.EncryptedBinary, redact: true
    timestamps(type: :utc_datetime)
  end
end
