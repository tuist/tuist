defmodule Tuist.Runs.Build do
  @moduledoc """
  A build represents a single build run of a project, such as when building an app from Xcode.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :scheme,
      :category,
      :status,
      :git_branch,
      :xcode_version,
      :macos_version,
      :account_id,
      :is_ci
    ],
    sortable: [:inserted_at, :duration]
  }

  @primary_key {:id, UUIDv7, autogenerate: false}
  schema "build_runs" do
    field :duration, :integer
    field :macos_version, :string
    field :xcode_version, :string
    field :is_ci, :boolean
    field :model_identifier, :string
    field :scheme, :string
    field :status, Ecto.Enum, values: [success: 0, failure: 1]
    field :category, Ecto.Enum, values: [clean: 0, incremental: 1]
    field :configuration, :string
    field :git_branch, :string
    field :git_commit_sha, :string
    field :git_ref, :string
    belongs_to :project, Tuist.Projects.Project
    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id
    has_many :issues, Tuist.Runs.BuildIssue, foreign_key: :build_run_id
    has_many :files, Tuist.Runs.BuildFile, foreign_key: :build_run_id
    has_many :targets, Tuist.Runs.BuildTarget, foreign_key: :build_run_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(build, attrs) do
    build
    |> cast(attrs, [
      :id,
      :duration,
      :macos_version,
      :xcode_version,
      :is_ci,
      :model_identifier,
      :scheme,
      :project_id,
      :account_id,
      :inserted_at,
      :status,
      :category,
      :configuration,
      :git_branch,
      :git_commit_sha,
      :git_ref
    ])
    |> validate_required([
      :id,
      :duration,
      :is_ci,
      :project_id,
      :account_id,
      :status
    ])
    |> validate_inclusion(:status, [:success, :failure])
  end
end
