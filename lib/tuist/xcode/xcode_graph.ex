defmodule Tuist.Xcode.XcodeGraph do
  @moduledoc """
  Xcode graph represents a graph similar to https://github.com/tuist/XcodeGraph.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "xcode_graphs" do
    field :name, :string

    belongs_to :command_event, Tuist.CommandEvents.Event
    has_many :xcode_projects, Tuist.Xcode.XcodeProject

    timestamps(type: :utc_datetime)
  end

  def create_changeset(graph, attrs) do
    graph
    |> cast(attrs, [:name, :command_event_id])
    |> validate_required([:name, :command_event_id])
    |> unique_constraint([:command_event_id])
  end
end
