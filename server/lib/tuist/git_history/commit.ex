defmodule Tuist.GitHistory.Commit do
  @moduledoc """
  One commit of a project's repository, as far back as the project's history
  window reaches. `generation` is Git's commit-graph generation number (1 for
  a commit whose parents are not stored, otherwise 1 + the highest parent
  generation), which lets ancestry walks stop descending below the commits
  they are looking for. Parents are in `Tuist.GitHistory.CommitParent`.
  """
  use Ecto.Schema

  schema "git_commits" do
    field :project_id, :integer
    field :sha, :string
    field :object_format, :string
    field :committed_at, :utc_datetime
    field :generation, :integer
    timestamps(type: :utc_datetime)
  end
end
