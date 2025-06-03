defmodule Tuist.Runs.BuildIssue do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "build_issues" do
    field :type, Ch, type: "Enum8('warning' = 0, 'error' = 1)"
    field :target, :string
    field :project, :string
    field :title, :string
    field :signature, :string

    field :step_type, Ch,
      type:
        "Enum8('c_compilation' = 0, 'swift_compilation' = 1, 'script_execution' = 2, 'create_static_library' = 3, 'linker' = 4, 'copy_swift_libs' = 5, 'compile_assets_catalog' = 6, 'compile_storyboard' = 7, 'write_auxiliary_file' = 8, 'link_storyboards' = 9, 'copy_resource_file' = 10, 'merge_swift_module' = 11, 'xib_compilation' = 12, 'swift_aggregated_compilation' = 13, 'precompile_bridging_header' = 14, 'other' = 15, 'validate_embedded_binary' = 16, 'validate' = 17)"

    field :path, :string
    field :message, :string
    field :starting_line, Ch, type: "UInt64"
    field :ending_line, Ch, type: "UInt64"
    field :starting_column, Ch, type: "UInt64"
    field :ending_column, Ch, type: "UInt64"

    belongs_to :build_run, Tuist.Runs.Build, type: Ecto.UUID
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end
end
