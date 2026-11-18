defmodule Tuist.GitHistory.Ref do
  @moduledoc """
  A branch or pull request of a repository, placed on the first-parent tree.
  The default branch has no parent and owns its first-parent history; any
  other ref forks from its parent at `fork_position` and owns the commits it
  added above it (`Tuist.GitHistory.Commit`'s `ref_id` and `position`). A pull
  request is named `pull/<number>`, since its branch name is reused.
  `head_sha` is the newest commit the ref was advanced to, and
  `head_observed_at` when the observation that moved it there was made.

  A `detached` ref is neither: it holds a listed commit that no branch or
  pull request owns (`Tuist.GitHistory.detach/3`), forking where the
  commit's first parents reach a commit a ref owns, so the commit's file
  changes have a place. Only `Tuist.GitHistory.FileChanges` reads it; to
  everything else its commits are owned by no ref. Its name is
  `detached:<sha>`, the commit it was created for, which Git refuses as a
  branch name. The name only keeps the ref unique: nothing finds a ref by
  it or reads the commit out of it.
  """
  use Ecto.Schema

  schema "git_refs" do
    field :repository_id, :integer
    field :name, :string
    field :parent_ref_id, :integer
    field :fork_position, :integer, default: 0
    field :head_sha, :string
    field :head_observed_at, :utc_datetime_usec
    field :detached, :boolean, default: false
    timestamps(type: :utc_datetime)
  end
end
