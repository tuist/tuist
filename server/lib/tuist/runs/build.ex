defmodule Tuist.Runs.Build do
  @moduledoc """
  A build represents a single build run of a project, such as when building an app from Xcode.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

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
      :git_ref,
      :xcode_version,
      :macos_version,
      :account_id,
      :is_ci,
      :ci_provider
    ],
    sortable: [:inserted_at, :duration]
  }

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "build_runs" do
    field :duration, Ch, type: "UInt64"
    field :macos_version, Ch, type: "String"
    field :xcode_version, Ch, type: "String"
    field :is_ci, Ch, type: "Bool"
    field :model_identifier, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :category, Ch, type: "Enum8('clean' = 0, 'incremental' = 1, 'unknown' = 127)"
    field :configuration, Ch, type: "String"
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :git_ref, Ch, type: "String"
    field :ci_run_id, Ch, type: "String"
    field :ci_project_handle, Ch, type: "String"
    field :ci_host, Ch, type: "String"

    field :ci_provider,
          Ch,
          type:
            "Enum8('github' = 0, 'gitlab' = 1, 'bitrise' = 2, 'circleci' = 3, 'buildkite' = 4, 'codemagic' = 5, 'unknown' = 127)"

    field :project_id, Ch, type: "UInt64"
    field :account_id, Ch, type: "UInt64"

    belongs_to :project, Tuist.Projects.Project, define_field: false
    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false

    has_many :issues, Tuist.Runs.BuildIssue, foreign_key: :build_run_id
    has_many :files, Tuist.Runs.BuildFile, foreign_key: :build_run_id
    has_many :targets, Tuist.Runs.BuildTarget, foreign_key: :build_run_id

    field :inserted_at, Ch, type: "DateTime64(6)"
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
      :ci_provider
    ])
    |> validate_required([
      :id,
      :duration,
      :is_ci,
      :project_id,
      :account_id,
      :status
    ])
    |> validate_number(:duration, greater_than_or_equal_to: 0)
  end

  def ensure_inserted_at(%__MODULE__{inserted_at: nil} = build) do
    inserted_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()

    %{build | inserted_at: inserted_at}
  end

  def ensure_inserted_at(%__MODULE__{} = build), do: build
end
