defmodule Tuist.Kura.RolloutEvent do
  @moduledoc """
  Audit trail entry for a rollout: automatic transitions (created, wave
  completed, paused by the gate, completed, superseded) and operator verbs
  (pause, resume, expedite, abort).

  Operator verbs record their actor and reason; expedites additionally
  record the source and target tags and whether the target tag had
  previously completed a rollout in this environment, so an expedited
  rollout is auditable after the incident.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Kura.Rollout

  @actions ~w(created wave_scheduled wave_completed paused resumed expedited aborted superseded completed)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_rollout_events" do
    field :action, :string
    field :actor, :string
    field :reason, :string
    field :metadata, :map, default: %{}

    belongs_to :rollout, Rollout, foreign_key: :kura_rollout_id, type: :binary_id

    # Sub-second precision so events recorded within one reconciler tick
    # keep a deterministic order in the audit trail.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end

  def actions, do: @actions

  def create_changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [:kura_rollout_id, :action, :actor, :reason, :metadata])
    |> validate_required([:kura_rollout_id, :action, :actor])
    |> validate_inclusion(:action, @actions)
    |> foreign_key_constraint(:kura_rollout_id)
  end
end
