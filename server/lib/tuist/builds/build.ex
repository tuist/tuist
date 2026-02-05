defmodule Tuist.Builds.Build do
  @moduledoc """
  A build represents a single build run of a project, such as when building an app from Xcode.
  This is a ClickHouse entity that stores build run data.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @status_values ["success", "failure"]
  @category_values ["clean", "incremental"]
  @ci_provider_values ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

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

    field :ci_provider, Ch,
      type: "Nullable(Enum8('github' = 0, 'gitlab' = 1, 'bitrise' = 2, 'circleci' = 3, 'buildkite' = 4, 'codemagic' = 5))"

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
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :microsecond)

    attrs
    |> Map.put(:id, id)
    |> Map.put(:inserted_at, Map.get(attrs, :inserted_at) || now)
    |> normalize_status()
    |> normalize_category()
    |> normalize_ci_provider()
    |> convert_datetime_field(:inserted_at)
    |> normalize_custom_tags()
    |> normalize_custom_values()
    |> ensure_defaults()
    |> ensure_all_fields()
  end

  defp normalize_status(attrs) do
    if Map.has_key?(attrs, :status) do
      case Map.get(attrs, :status) do
        :success -> Map.put(attrs, :status, "success")
        :failure -> Map.put(attrs, :status, "failure")
        "success" -> attrs
        "failure" -> attrs
        0 -> Map.put(attrs, :status, "success")
        1 -> Map.put(attrs, :status, "failure")
        _ -> Map.put(attrs, :status, nil)
      end
    else
      Map.put(attrs, :status, "success")
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
      _ -> Map.put(attrs, :category, nil)
    end
  end

  @ci_provider_by_index %{
    0 => "github",
    1 => "gitlab",
    2 => "bitrise",
    3 => "circleci",
    4 => "buildkite",
    5 => "codemagic"
  }

  defp normalize_ci_provider(attrs) do
    value = Map.get(attrs, :ci_provider)
    normalized = coerce_ci_provider(value)
    if normalized == value, do: attrs, else: Map.put(attrs, :ci_provider, normalized)
  end

  defp coerce_ci_provider(nil), do: nil
  defp coerce_ci_provider(value) when is_atom(value), do: value |> Atom.to_string() |> validate_ci_provider()
  defp coerce_ci_provider(value) when is_integer(value), do: Map.get(@ci_provider_by_index, value)
  defp coerce_ci_provider(value) when is_binary(value), do: validate_ci_provider(value)
  defp coerce_ci_provider(_), do: nil

  defp validate_ci_provider(value) when value in @ci_provider_values, do: value
  defp validate_ci_provider(_), do: nil

  defp convert_datetime_field(attrs, field) do
    case Map.get(attrs, field) do
      %DateTime{} = dt ->
        Map.put(attrs, field, dt |> DateTime.to_naive() |> ensure_microsecond_precision())

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

  defp ensure_all_fields(attrs) do
    struct = __struct__()

    Enum.reduce(__schema__(:fields), attrs, fn field, acc ->
      Map.put_new(acc, field, Map.get(struct, field))
    end)
  end

  defp normalize_custom_tags(attrs) do
    case Map.get(attrs, :custom_tags) do
      nil -> attrs
      tags when is_list(tags) -> Map.put(attrs, :custom_tags, Enum.filter(tags, &is_binary/1))
      _ -> Map.put(attrs, :custom_tags, [])
    end
  end

  defp normalize_custom_values(attrs) do
    case Map.get(attrs, :custom_values) do
      nil ->
        attrs

      values when is_map(values) ->
        filtered =
          for {key, value} <- values, is_binary(key) and is_binary(value), into: %{} do
            {key, value}
          end

        Map.put(attrs, :custom_values, filtered)

      _ ->
        Map.put(attrs, :custom_values, %{})
    end
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

  def valid_status?(status) when status in @status_values, do: true
  def valid_status?(_), do: false

  def valid_category?(category) when category in @category_values, do: true
  def valid_category?(_), do: false

  def valid_ci_provider?(provider) when provider in @ci_provider_values, do: true
  def valid_ci_provider?(_), do: false
end
