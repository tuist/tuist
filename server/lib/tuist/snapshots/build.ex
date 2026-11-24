defmodule Tuist.Snapshots.Build do
  @moduledoc """
  One upload of a snapshot set at a commit: the images a test run recorded,
  compared with the images of its baseline build.

  A build starts `uploading` while the client puts the images the server
  lacks, becomes `processing` once the client completes it, and `processed`
  after `Tuist.Snapshots.Workers.ProcessBuildWorker` compared it with its
  baseline. Builds on the project's default branch are baselines without
  review; any other build with changes or removals needs a review, which
  approves or rejects them.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  @states ~w(uploading processing processed failed)

  schema "snapshot_builds" do
    field :set_name, :string
    field :git_commit_sha, :string
    field :git_branch, :string
    field :git_ref, :string
    field :git_remote_url_origin, :string
    field :merge_base_sha, :string
    field :pull_request_number, :integer
    field :pull_request_title, :string
    field :is_ci, :boolean, default: false
    field :build_system, :string
    field :state, :string, default: "uploading"
    field :unchanged_count, :integer, default: 0
    field :changed_count, :integer, default: 0
    field :added_count, :integer, default: 0
    field :removed_count, :integer, default: 0
    field :renamed_count, :integer, default: 0
    field :skipped_count, :integer, default: 0
    field :selective, :boolean, default: false
    field :approved_at, :utc_datetime
    field :processed_at, :utc_datetime
    field :changes_signature, :string
    field :approved_by_github_handle, :string
    field :rejected_at, :utc_datetime
    field :rejected_by_github_handle, :string
    field :github_check_run_id, :integer

    belongs_to :project, Tuist.Projects.Project, type: :integer
    belongs_to :baseline_build, __MODULE__
    belongs_to :approved_by_account, Account, type: :integer
    belongs_to :approved_from_build, __MODULE__
    belongs_to :rejected_by_account, Account, type: :integer
    has_many :images, Tuist.Snapshots.Image

    timestamps(type: :utc_datetime)
  end

  def create_changeset(build, attrs) do
    build
    |> cast(attrs, [
      :project_id,
      :set_name,
      :git_commit_sha,
      :git_branch,
      :git_ref,
      :git_remote_url_origin,
      :merge_base_sha,
      :pull_request_number,
      :pull_request_title,
      :is_ci,
      :build_system,
      :selective
    ])
    |> validate_required([:project_id, :set_name])
    |> validate_length(:pull_request_title, max: 1_024)
    |> validate_format(:set_name, ~r/^[A-Za-z0-9._\-\/ ]{1,100}$/)
  end

  def state_changeset(build, attrs) do
    build
    |> cast(attrs, [
      :state,
      :baseline_build_id,
      :unchanged_count,
      :changed_count,
      :added_count,
      :removed_count,
      :renamed_count,
      :skipped_count,
      :processed_at,
      :changes_signature
    ])
    |> validate_inclusion(:state, @states)
  end

  def check_run_changeset(build, attrs), do: cast(build, attrs, [:github_check_run_id])

  @review_fields [
    :approved_at,
    :approved_by_account_id,
    :approved_by_github_handle,
    :approved_from_build_id,
    :rejected_at,
    :rejected_by_account_id,
    :rejected_by_github_handle
  ]

  @doc "Records a review. Approving clears a rejection and rejecting clears an approval."
  def review_changeset(build, attrs) do
    cleared = Map.new(@review_fields, &{&1, nil})
    cast(build, Map.merge(cleared, attrs), @review_fields)
  end
end
