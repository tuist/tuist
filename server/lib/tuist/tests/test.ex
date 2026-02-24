defmodule Tuist.Tests.Test do
  @moduledoc """
  A test run represents a single test execution of a project.
  This is a ClickHouse entity that stores test run data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :scheme,
      :status,
      :git_branch,
      :xcode_version,
      :macos_version,
      :account_id,
      :is_ci,
      :build_system
    ],
    sortable: [:ran_at, :duration, :inserted_at]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_runs" do
    field :duration, Ch, type: "Int32"
    field :macos_version, Ch, type: "String"
    field :xcode_version, Ch, type: "String"
    field :is_ci, :boolean
    field :model_identifier, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :status, Ch, type: "LowCardinality(String)"
    field :is_flaky, :boolean, default: false
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :git_ref, Ch, type: "String"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :project_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :build_run_id, Ch, type: "Nullable(UUID)"
    field :gradle_build_id, Ch, type: "Nullable(UUID)"
    field :ci_run_id, Ch, type: "String", default: ""
    field :ci_project_handle, Ch, type: "String", default: ""
    field :ci_host, Ch, type: "String", default: ""
    field :ci_provider, Ch, type: "LowCardinality(Nullable(String))"
    field :build_system, Ch, type: "LowCardinality(String)", default: "xcode"

    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false
    belongs_to :build_run, Tuist.Builds.Build, foreign_key: :build_run_id, define_field: false
    belongs_to :gradle_build, Tuist.Gradle.Build, foreign_key: :gradle_build_id, define_field: false
    has_many :test_case_runs, Tuist.Tests.TestCaseRun, foreign_key: :test_run_id

    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(test_run, attrs) do
    test_run
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
      :status,
      :is_flaky,
      :git_branch,
      :git_commit_sha,
      :git_ref,
      :ran_at,
      :inserted_at,
      :build_run_id,
      :gradle_build_id,
      :ci_run_id,
      :ci_project_handle,
      :ci_host,
      :ci_provider,
      :build_system
    ])
    |> validate_required([
      :id,
      :duration,
      :is_ci,
      :project_id,
      :account_id,
      :status,
      :ran_at,
      :build_system
    ])
    |> validate_inclusion(:status, ["success", "failure", "skipped"])
    |> validate_inclusion(:build_system, ["xcode", "gradle"])
    |> validate_inclusion(:ci_provider, Tuist.Tests.valid_ci_providers())
  end
end
