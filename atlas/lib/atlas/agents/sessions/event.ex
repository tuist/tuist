defmodule Atlas.Agents.Sessions.Event do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Agents.Sessions.Session

  @types ~w(run agent tool_call subagent operation secrets compact llm_turn)
  @phases ~w(start stop exception resolve access)

  schema "agent_session_events" do
    field :type, :string
    field :name, :string
    field :phase, :string
    field :duration_ms, :integer
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime_usec

    belongs_to :agent_session, Session

    timestamps(updated_at: false)
  end

  def changeset(attrs) do
    {agent_session_id, attrs} = Map.pop(attrs, :agent_session_id)

    %__MODULE__{agent_session_id: agent_session_id}
    |> cast(attrs, [:type, :name, :phase, :duration_ms, :metadata, :occurred_at])
    |> validate_required([:agent_session_id, :type, :phase, :occurred_at])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:phase, @phases)
    |> foreign_key_constraint(:agent_session_id)
  end
end
