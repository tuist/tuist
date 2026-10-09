defmodule Tuist.Tests.CoverageCommitTarget do
  @moduledoc """
  A complete commit's coverage of one target, with coverage carried in for
  skipped tests applied, as `Tuist.Tests.Coverage.Commits.targets/3` reads
  it. Rewritten whole at every `commit_version`; a reader keeps the rows of
  the highest one. `ref_id` and `position` are the place the commit's file
  rows (`Tuist.Tests.CoverageFileDelta`) were written at, 0 when it has no
  ref: the rows are current while the commit's version and place match.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_commit_targets" do
    field :project_id, Ch, type: "Int64"
    field :git_commit_sha, Ch, type: "String"
    field :target, Ch, type: "String"
    field :files_count, Ch, type: "UInt32"
    field :covered_lines, Ch, type: "UInt64"
    field :executable_lines, Ch, type: "UInt64"
    field :commit_version, Ch, type: "UInt64"
    field :ref_id, Ch, type: "Int64", default: 0
    field :position, Ch, type: "UInt32", default: 0
    field :committed_at, Ch, type: "DateTime64(6)"
  end
end
