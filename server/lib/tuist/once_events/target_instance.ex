defmodule Tuist.OnceEvents.TargetInstance do
  @moduledoc """
  A `TargetInstance` event: the run-local `target_instance_id` resolved to the
  stable `target_id` it instantiates.
  """
  use Ecto.Schema

  alias Tuist.OnceEvents.Run

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_target_instances" do
    belongs_to :run, Run, foreign_key: :once_run_id, type: UUIDv7
    field :target_instance_id, :string
    field :target_id, :string
    field :configuration_digest, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
