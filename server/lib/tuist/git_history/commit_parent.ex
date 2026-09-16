defmodule Tuist.GitHistory.CommitParent do
  @moduledoc """
  A parent edge of a stored commit. `position` keeps Git's parent order, so
  position 0 is the first parent. The parent need not be stored itself: the
  edge to a commit outside the history window is kept, and the walk simply
  ends there.
  """
  use Ecto.Schema

  @primary_key false
  schema "git_commit_parents" do
    field :project_id, :integer
    field :child_sha, :string
    field :parent_sha, :string
    field :position, :integer
  end
end
