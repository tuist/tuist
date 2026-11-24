defmodule Tuist.Pulse.Investigations.BriefStep do
  @moduledoc """
  A stored mitigation step and its feedback. Existing command, undo and
  safety fields are retained for historical records; the backend no longer
  generates steps. Status feedback reaches the evaluator through
  `Tuist.Pulse.Investigations.set_step_status/4`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Pulse.Investigations.Brief

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_brief_steps" do
    belongs_to :account, Account, type: :integer
    belongs_to :brief, Brief, type: UUIDv7
    field :position, :integer
    field :kind, Ecto.Enum, values: [:rollback_server, :stop_promotion, :pause_queue, :slow_queue, :drain_kura_node]
    field :title, :string
    field :detail, :string
    field :command, :string
    field :reverse_command, :string
    field :safety, Ecto.Enum, values: [:safe, :unsafe, :unknown]
    field :safety_reason, :string
    field :status, Ecto.Enum, values: [:proposed, :taken, :helped, :did_not_help], default: :proposed
    belongs_to :status_by, User, type: :integer
    field :status_changed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
