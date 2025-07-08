defmodule Tuist.Xcode.Postgres.XcodeGraph do
  @moduledoc """
  Xcode graph represents a graph similar to https://github.com/tuist/XcodeGraph.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "xcode_graphs" do
    field :name, :string

    # This represents an estimation of the time that it took to build the binaries
    # used in the graph. This number is calculated client-side using the graph information
    # and assuming uncapped parallelism.
    field :binary_build_duration, :integer

    belongs_to :command_event, Tuist.CommandEvents.Event
    has_many :xcode_projects, Tuist.Xcode.Postgres.XcodeProject

    timestamps(type: :utc_datetime)
  end

  def create_changeset(graph, attrs) do
    graph
    |> cast(attrs, [:name, :binary_build_duration, :command_event_id])
    |> validate_required([:name, :command_event_id])
    |> unique_constraint([:command_event_id])
  end
end
