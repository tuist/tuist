defmodule Tuist.GitHistory.Commit do
  @moduledoc """
  One commit of a repository, as far back as the history
  window reaches. `generation` is Git's commit-graph generation number (1 for
  a commit whose parents are not stored, otherwise 1 + the highest parent
  generation), which lets ancestry walks stop descending below the commits
  they are looking for. Parents are in `Tuist.GitHistory.CommitParent`.

  `ref_id` and `position` place the commit on a ref's first-parent segment
  (`Tuist.GitHistory.Ref`); both are nil for a commit no ref owns.
  """
  use Ecto.Schema

  schema "git_commits" do
    field :repository_id, :integer
    field :sha, :string
    field :object_format, :string
    field :committed_at, :utc_datetime
    field :generation, :integer
    field :ref_id, :integer
    field :position, :integer
    timestamps(type: :utc_datetime)
  end
end
