defmodule Tuist.GitHistory.CommitListing do
  @moduledoc """
  Marks that a commit's file listing (`Tuist.GitHistory.CommitFile`, in
  ClickHouse) is stored, with how many files it has and whether the client
  stopped at the limit. The listing itself expires with the coverage file
  detail; a row older than that retention counts as missing and the next
  upload replaces it. Only a listing that is neither expired nor truncated
  is complete (`Tuist.GitHistory.listing_complete?/2`).

  `changes_ref_id` and `changes_position` are the place the commit's file
  changes were written for (`Tuist.GitHistory.FileChanges`), nil until they
  are, and `changes_expires_at` until when those rows are kept.
  """
  use Ecto.Schema

  @primary_key false
  schema "git_commit_listings" do
    field :repository_id, :integer
    field :sha, :string
    field :files_count, :integer
    field :truncated, :boolean, default: false
    field :inserted_at, :utc_datetime
    field :changes_ref_id, :integer
    field :changes_position, :integer
    field :changes_expires_at, :utc_datetime
  end
end
