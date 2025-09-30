defmodule Tuist.Runs.Test do
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
      :is_ci
    ],
    sortable: [:ran_at, :duration, :inserted_at]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_runs" do
    field :duration, Ch, type: "Int32"
    field :macos_version, :string
    field :xcode_version, :string
    field :is_ci, :boolean
    field :model_identifier, :string
    field :scheme, :string
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :git_branch, :string
    field :git_commit_sha, :string
    field :git_ref, :string
    field :ran_at, Ch, type: "DateTime64(6)"
    field :project_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    # has_many :test_cases, Tuist.Runs.TestCase, foreign_key: :test_run_id

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
      :git_branch,
      :git_commit_sha,
      :git_ref,
      :ran_at,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :duration,
      :macos_version,
      :xcode_version,
      :is_ci,
      :project_id,
      :account_id,
      :status,
      :ran_at
    ])
    |> validate_inclusion(:status, [0, 1, :success, :failure])
  end
end
