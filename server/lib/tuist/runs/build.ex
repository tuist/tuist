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
      :configuration,
      :category,
      :status,
      :git_branch,
      :xcode_version,
      :macos_version,
      :account_id,
      :is_ci,
      :ci_provider,
      :cacheable_tasks_count
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
    field :ci_run_id, :string
    field :ci_project_handle, :string
    field :ci_host, :string
    field :ci_provider, Ecto.Enum, values: [github: 0, gitlab: 1, bitrise: 2, circleci: 3, buildkite: 4, codemagic: 5]
    field :cacheable_task_remote_hits_count, :integer, default: 0
    field :cacheable_task_local_hits_count, :integer, default: 0
    field :cacheable_tasks_count, :integer, default: 0
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
      :git_ref,
      :ci_run_id,
      :ci_project_handle,
      :ci_host,
      :ci_provider,
      :cacheable_task_remote_hits_count,
      :cacheable_task_local_hits_count,
      :cacheable_tasks_count
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
    |> validate_inclusion(:ci_provider, [:github, :gitlab, :bitrise, :circleci, :buildkite, :codemagic])
    |> unique_constraint(:id, match: :suffix, name: "build_runs_pkey")
  end
end
