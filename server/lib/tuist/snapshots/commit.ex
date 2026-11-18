defmodule Tuist.Snapshots.Commit do
  @moduledoc """
  A commit's snapshots, pooled over every build uploaded for it: each set
  and shard is a build, and so is each rerun. It is what a commit's review
  page shows, the way `Tuist.Tests.CoverageCommit` pools a commit's coverage
  runs.

  `Tuist.Snapshots.refresh_commit/2` republishes the row whenever one of the
  commit's builds is created, processed, reviewed or fails, so the counts,
  the `status` (the worst verdict among its sets) and the latest review
  always describe the builds.

  `completed_at` is when the commit's CI signalled that every job reported,
  the same signal that completes its coverage (`tuist coverage complete`).
  Until then more builds may land, and a commit with no build yet can hold
  the signal, so it isn't found until a build lands (`runs_count` is 0).
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  @statuses ~w(processing failed rejected needs_review approved passed baseline)

  def statuses, do: @statuses

  schema "snapshot_commits" do
    field :git_commit_sha, :string
    field :git_branch, :string
    field :pull_request_number, :integer
    field :pull_request_title, :string
    field :status, :string, default: "processing"
    field :unchanged_count, :integer, default: 0
    field :changed_count, :integer, default: 0
    field :added_count, :integer, default: 0
    field :removed_count, :integer, default: 0
    field :renamed_count, :integer, default: 0
    field :skipped_count, :integer, default: 0
    field :runs_count, :integer, default: 0
    field :set_names, {:array, :string}, default: []
    field :baseline_commit_sha, :string
    field :baseline_git_branch, :string
    field :approved_at, :utc_datetime
    field :approved_by_github_handle, :string
    field :rejected_at, :utc_datetime
    field :rejected_by_github_handle, :string
    field :completed_at, :utc_datetime
    field :last_uploaded_at, :utc_datetime

    belongs_to :project, Tuist.Projects.Project, type: :integer
    belongs_to :approved_by_account, Account, type: :integer
    belongs_to :rejected_by_account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  @doc "The commit is complete once its CI signalled it, or `:in_progress` until then."
  def completeness(%__MODULE__{completed_at: %DateTime{}}), do: :complete
  def completeness(%__MODULE__{}), do: :in_progress
end
