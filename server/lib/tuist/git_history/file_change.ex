defmodule Tuist.GitHistory.FileChange do
  @moduledoc """
  A path a commit changed against the nearest listed commit below it on the
  first-parent tree (`Tuist.GitHistory.FileChanges`), keyed by the commit's
  place (`ref_id`, `position`). An empty `git_blob_id` marks a path the
  commit no longer has, and `is_deleted` a row retired because its key
  moved.
  """
  use Ecto.Schema

  @primary_key false
  schema "git_file_changes" do
    field :repository_id, Ch, type: "Int64"
    field :ref_id, Ch, type: "Int64"
    field :position, Ch, type: "UInt32"
    field :generation, Ch, type: "UInt32"
    field :sha, Ch, type: "String"
    field :path, Ch, type: "String"
    field :git_blob_id, Ch, type: "String"
    field :mode, Ch, type: "UInt32"
    field :expires_at, Ch, type: "DateTime"
    field :row_version, Ch, type: "UInt64"
    field :is_deleted, Ch, type: "UInt8", default: 0
  end
end
