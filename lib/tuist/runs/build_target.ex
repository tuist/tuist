defmodule Tuist.Runs.BuildTarget do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [
      :build_run_id,
      :name,
      :project,
      :build_duration,
      :compilation_duration,
      :status
    ],
    sortable: [:name, :compilation_duration, :build_duration]
  }

  @primary_key false
  schema "build_targets" do
    field :name, :string
    field :project, :string
    field :build_duration, Ch, type: "UInt64"
    field :compilation_duration, Ch, type: "UInt64"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"

    belongs_to :build_run, Tuist.Runs.Build, type: Ecto.UUID

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end
end
