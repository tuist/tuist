defmodule Tuist.Sandboxes.SandboxCommand do
  @moduledoc """
  A command started through `Tuist.Sandboxes.Commands`. The guest holds its
  output and exit code; the row is what lets a sandbox run several at once,
  list them, and know when the last one ended. Environment values are never
  stored.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.Sandbox

  @statuses [:running, :exited, :timed_out, :cancelled, :lost]

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "sandbox_commands" do
    field :command, :string
    field :cwd, :string
    field :stdin, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :running
    field :exit_code, :integer
    field :deadline_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :sandbox, Sandbox, type: :binary_id
    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
end
