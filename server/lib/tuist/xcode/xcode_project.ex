defmodule Tuist.Xcode.XcodeProject do
  @moduledoc false
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "xcode_projects" do
    field :id, :string
    field :name, :string
    field :path, :string
    field :xcode_graph_id, Ch, type: "UUID"
    field :command_event_id, Ch, type: "UUID"

    belongs_to :command_event, Tuist.CommandEvents.Event,
      foreign_key: :command_event_id,
      references: :id,
      define_field: false

    belongs_to :xcode_graph, Tuist.Xcode.XcodeGraph,
      foreign_key: :xcode_graph_id,
      references: :id,
      define_field: false

    has_many :xcode_targets, Tuist.Xcode.XcodeTarget,
      foreign_key: :xcode_project_id,
      references: :id

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end
end
