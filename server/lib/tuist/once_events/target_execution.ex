defmodule Tuist.OnceEvents.TargetExecution do
  @moduledoc """
  A `TargetQueued` event: which target instance a run-local
  `target_execution_id` executes. Actions only name the execution.
  """
  use Ecto.Schema

  alias Tuist.OnceEvents.Run

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_target_executions" do
    belongs_to :run, Run, foreign_key: :once_run_id, type: UUIDv7
    field :target_execution_id, :string
    field :target_instance_id, :string
    field :attempt, :integer, default: 0

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
