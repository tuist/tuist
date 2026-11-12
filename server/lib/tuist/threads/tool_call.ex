defmodule Tuist.Threads.ToolCall do
  @moduledoc "A reserved tool effect is never automatically dispatched twice."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thread_tool_calls" do
    field :run_id, :binary_id
    field :message_id, :binary_id
    field :fingerprint, :binary
    field :name, :string
    field :status, :string, default: "executing"
    field :checkpointed, :boolean, default: false
    field :result, Tuist.Vault.Binary, redact: true
    timestamps(type: :utc_datetime)
  end
end
