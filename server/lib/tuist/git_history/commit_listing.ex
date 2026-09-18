defmodule Tuist.GitHistory.CommitListing do
  @moduledoc """
  Marks that a commit's file listing (`Tuist.GitHistory.CommitFile`, in
  ClickHouse) is stored, with how many files it has and whether the client
  stopped at the limit. The listing itself expires with the coverage file
  detail; this row goes with it (`Tuist.GitHistory.prune/1`).
  """
  use Ecto.Schema

  @primary_key false
  schema "git_commit_listings" do
    field :repository_id, :integer
    field :sha, :string
    field :files_count, :integer
    field :truncated, :boolean, default: false
    field :inserted_at, :utc_datetime
  end
end
