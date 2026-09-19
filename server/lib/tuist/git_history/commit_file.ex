defmodule Tuist.GitHistory.CommitFile do
  @moduledoc """
  One file of a commit's tree, with the blob it had: the listing the client
  takes from `git ls-files --stage` at a clean checkout of the commit. Keyed
  by repository and commit, not by run, since the tree is the commit's and a
  sharded run must not upload it once per shard.

  The listing is what coverage measures against (the source files that exist
  at the commit, so a module no test ran is reported as never measured rather
  than left out), where the tracked files come from (the project's globs
  applied to it at read time), and the blob of any path at any ancestor for
  evidence reuse. Stored in ClickHouse, expiring with the coverage file
  detail.
  """
  use Ecto.Schema

  @primary_key false
  schema "git_commit_files" do
    field :repository_id, Ch, type: "Int64"
    field :sha, Ch, type: "String"
    field :path, Ch, type: "String"
    field :git_blob_id, Ch, type: "String", default: ""
    field :mode, Ch, type: "UInt32", default: 0
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
