defmodule Tuist.Runs.BuildFile do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [
      :build_run_id,
      :type,
      :target,
      :project,
      :path,
      :compilation_duration
    ],
    sortable: [:compilation_duration, :path]
  }

  @primary_key false
  schema "build_files" do
    field :type, Ch, type: "Enum8('swift' = 0, 'c' = 1)"
    field :target, :string
    field :project, :string
    field :path, :string
    field :compilation_duration, Ch, type: "UInt64"

    belongs_to :build_run, Tuist.Runs.Build, type: Ecto.UUID

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end
end
