defmodule Tuist.GitHistory.Ref do
  @moduledoc """
  A branch or pull request of a repository, placed on the first-parent tree.
  The default branch has no parent and owns its first-parent history; any
  other ref forks from its parent at `fork_position` and owns the commits it
  added above it (`Tuist.GitHistory.Commit`'s `ref_id` and `position`). A pull
  request is named `pull/<number>`, since its branch name is reused.
  `head_sha` is the newest commit the ref was advanced to.
  """
  use Ecto.Schema

  schema "git_refs" do
    field :repository_id, :integer
    field :name, :string
    field :parent_ref_id, :integer
    field :fork_position, :integer, default: 0
    field :head_sha, :string
    timestamps(type: :utc_datetime)
  end
end
