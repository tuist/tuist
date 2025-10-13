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

    field :inserted_at, Ch, type: "DateTime"
  end

  @defaults %{
    macos_version: "",
    xcode_version: "",
    model_identifier: "",
    scheme: "",
    category: "unknown",
    configuration: "",
    git_branch: "",
    git_commit_sha: "",
    git_ref: "",
    ci_run_id: "",
    ci_project_handle: "",
    ci_host: "",
    ci_provider: "unknown"
  }

  def changeset(attrs) do
    %__MODULE__{}
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
    |> case do
      %{valid?: true}  = changeset ->
        changeset

    |> Map.from_struct()
    |> Map.get(:changes)
    |> add_defaults()
    |> add_inserted_at()
      changeset ->
        changeset
    end

  end

  defp add_defaults(nil), do: @defaults

  defp add_defaults(changes) do
    Enum.reduce(@defaults, changes, fn {field, default}, acc ->
      case Map.fetch(acc, field) do
        :error -> Map.put(acc, field, default)
        {:ok, nil} -> Map.put(acc, field, default)
        {:ok, _value} -> acc
      end
    end)
  end

  def add_inserted_at(build) do
    inserted_at =
      case Map.get(build, :inserted_at) do
        %NaiveDateTime{} = value ->
          value

        %DateTime{} = value ->
          value
          |> DateTime.truncate(:second)
          |> DateTime.to_naive()

        nil ->
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.to_naive()
      end

    Map.put(build, :inserted_at, inserted_at)
  end
end
