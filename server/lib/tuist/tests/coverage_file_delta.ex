defmodule Tuist.Tests.CoverageFileDelta do
  @moduledoc """
  A file's coverage at a complete commit, stored where it differs from the
  commit's previous complete commit (`Tuist.Tests.Coverage.Deltas`). Keyed by
  the commit's place on the first-parent tree; `executable_lines = 0` marks a
  file the commit no longer has, `kind` `checkpoint` a full snapshot, and
  `is_deleted` a row retired because its key moved.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_file_deltas" do
    field :project_id, Ch, type: "Int64"
    field :ref_id, Ch, type: "Int64"
    field :position, Ch, type: "UInt32"
    field :path, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :base_sha, Ch, type: "String", default: ""
    field :kind, Ch, type: "Enum8('delta' = 1, 'checkpoint' = 2)"
    field :covered_lines, Ch, type: "UInt32"
    field :executable_lines, Ch, type: "UInt32"
    field :commit_version, Ch, type: "UInt64"
    field :committed_at, Ch, type: "DateTime64(6)"
    field :row_version, Ch, type: "UInt64"
    field :is_deleted, Ch, type: "UInt8", default: 0
  end
end
