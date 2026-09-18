defmodule Tuist.GitHistory.BranchHead do
  @moduledoc """
  The newest commit a repository's runs or the VCS provider reported for a
  branch, and when. One row per branch, replaced as newer heads arrive.
  """
  use Ecto.Schema

  @primary_key false
  schema "git_branch_heads" do
    field :repository_id, :integer
    field :branch, :string
    field :sha, :string
    field :seen_at, :utc_datetime
  end
end
