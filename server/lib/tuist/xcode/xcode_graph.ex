defmodule Tuist.Xcode.XcodeGraph do
  @moduledoc false
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "xcode_graphs" do
    field :id, :string
    field :name, :string
    field :command_event_id, Ch, type: "UUID"
    field :binary_build_duration, Ch, type: "Nullable(UInt32)"

    has_many :xcode_projects, Tuist.Xcode.XcodeProject,
      foreign_key: :xcode_graph_id,
      references: :id

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end
end
