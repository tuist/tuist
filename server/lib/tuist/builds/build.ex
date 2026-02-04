defmodule Tuist.Builds.Build do
  @moduledoc """
  A build represents a single build run of a project, such as when building an app from Xcode.
  This is a ClickHouse entity that stores build run data.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

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
      :cacheable_tasks_count,
      :custom_tags
    ],
    sortable: [:inserted_at, :duration]
  }

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "build_runs" do
    field :duration, Ch, type: "Int32"
    field :project_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :macos_version, Ch, type: "Nullable(String)"
    field :xcode_version, Ch, type: "Nullable(String)"
    field :is_ci, :boolean, default: false
    field :model_identifier, Ch, type: "Nullable(String)"
    field :scheme, Ch, type: "Nullable(String)"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :category, Ch, type: "Nullable(Enum8('clean' = 0, 'incremental' = 1))"
    field :configuration, Ch, type: "Nullable(String)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :ci_run_id, Ch, type: "Nullable(String)"
    field :ci_project_handle, Ch, type: "Nullable(String)"
    field :ci_host, Ch, type: "Nullable(String)"
    field :ci_provider, Ch, type: "Nullable(Enum8('github' = 0, 'gitlab' = 1, 'bitrise' = 2, 'circleci' = 3, 'buildkite' = 4, 'codemagic' = 5))"
    field :cacheable_task_remote_hits_count, Ch, type: "Int32", default: 0
    field :cacheable_task_local_hits_count, Ch, type: "Int32", default: 0
    field :cacheable_tasks_count, Ch, type: "Int32", default: 0
    field :custom_tags, {:array, :string}, default: []
    field :custom_values, Ch, type: "Map(String, String)", default: %{}
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :project, Tuist.Projects.Project, define_field: false
    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false
    has_many :issues, Tuist.Builds.BuildIssue, foreign_key: :build_run_id
    has_many :files, Tuist.Builds.BuildFile, foreign_key: :build_run_id
    has_many :targets, Tuist.Builds.BuildTarget, foreign_key: :build_run_id
  end

  def changeset(attrs) do
    id = Map.get(attrs, :id) || UUIDv7.generate()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)

    attrs
    |> Map.put(:id, id)
    |> Map.put_new(:inserted_at, now)
    |> normalize_status()
    |> normalize_category()
    |> normalize_ci_provider()
    |> convert_datetime_field(:inserted_at)
    |> ensure_defaults()
  end

  defp normalize_status(attrs) do
    case Map.get(attrs, :status) do
      :success -> Map.put(attrs, :status, "success")
      :failure -> Map.put(attrs, :status, "failure")
      "success" -> attrs
      "failure" -> attrs
      0 -> Map.put(attrs, :status, "success")
      1 -> Map.put(attrs, :status, "failure")
      _ -> Map.put(attrs, :status, "success")
    end
  end

  defp normalize_category(attrs) do
    case Map.get(attrs, :category) do
      nil -> attrs
      :clean -> Map.put(attrs, :category, "clean")
      :incremental -> Map.put(attrs, :category, "incremental")
      "clean" -> attrs
      "incremental" -> attrs
      0 -> Map.put(attrs, :category, "clean")
      1 -> Map.put(attrs, :category, "incremental")
      _ -> attrs
    end
  end

  defp normalize_ci_provider(attrs) do
    case Map.get(attrs, :ci_provider) do
      nil -> attrs
      :github -> Map.put(attrs, :ci_provider, "github")
      :gitlab -> Map.put(attrs, :ci_provider, "gitlab")
      :bitrise -> Map.put(attrs, :ci_provider, "bitrise")
      :circleci -> Map.put(attrs, :ci_provider, "circleci")
      :buildkite -> Map.put(attrs, :ci_provider, "buildkite")
      :codemagic -> Map.put(attrs, :ci_provider, "codemagic")
      value when is_binary(value) -> attrs
      0 -> Map.put(attrs, :ci_provider, "github")
      1 -> Map.put(attrs, :ci_provider, "gitlab")
      2 -> Map.put(attrs, :ci_provider, "bitrise")
      3 -> Map.put(attrs, :ci_provider, "circleci")
      4 -> Map.put(attrs, :ci_provider, "buildkite")
      5 -> Map.put(attrs, :ci_provider, "codemagic")
      _ -> attrs
    end
  end

  defp convert_datetime_field(attrs, field) do
    case Map.get(attrs, field) do
      %DateTime{} = dt ->
        Map.put(attrs, field, DateTime.to_naive(dt) |> ensure_microsecond_precision())

      %NaiveDateTime{} = ndt ->
        Map.put(attrs, field, ensure_microsecond_precision(ndt))

      _ ->
        attrs
    end
  end

  defp ensure_microsecond_precision(%NaiveDateTime{} = ndt) do
    %{ndt | microsecond: {elem(ndt.microsecond, 0), 6}}
  end

  defp ensure_defaults(attrs) do
    attrs
    |> Map.put_new(:is_ci, false)
    |> Map.put_new(:cacheable_task_remote_hits_count, 0)
    |> Map.put_new(:cacheable_task_local_hits_count, 0)
    |> Map.put_new(:cacheable_tasks_count, 0)
    |> Map.put_new(:custom_tags, [])
    |> Map.put_new(:custom_values, %{})
  end

  def normalize_enums(build) do
    %{
      build
      | status: status_string_to_atom(build.status),
        category: category_string_to_atom(build.category),
        ci_provider: ci_provider_string_to_atom(build.ci_provider)
    }
  end

  defp status_string_to_atom("success"), do: :success
  defp status_string_to_atom("failure"), do: :failure
  defp status_string_to_atom(_), do: :success

  defp category_string_to_atom(nil), do: nil
  defp category_string_to_atom("clean"), do: :clean
  defp category_string_to_atom("incremental"), do: :incremental
  defp category_string_to_atom(_), do: nil

  defp ci_provider_string_to_atom(nil), do: nil
  defp ci_provider_string_to_atom("github"), do: :github
  defp ci_provider_string_to_atom("gitlab"), do: :gitlab
  defp ci_provider_string_to_atom("bitrise"), do: :bitrise
  defp ci_provider_string_to_atom("circleci"), do: :circleci
  defp ci_provider_string_to_atom("buildkite"), do: :buildkite
  defp ci_provider_string_to_atom("codemagic"), do: :codemagic
  defp ci_provider_string_to_atom(_), do: nil
end
