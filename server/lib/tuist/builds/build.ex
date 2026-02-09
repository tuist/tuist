defmodule Tuist.Builds.Build do
  @moduledoc """
  A build represents a single build run of a project, such as when building an app from Xcode.
  This is a ClickHouse entity that stores build run data.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Changeset

  @status_values ["success", "failure"]
  @category_values ["clean", "incremental"]
  @ci_provider_values ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]

  @ci_provider_by_index %{
    0 => "github",
    1 => "gitlab",
    2 => "bitrise",
    3 => "circleci",
    4 => "buildkite",
    5 => "codemagic"
  }

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
    field :is_ci, :boolean
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

  def create_changeset(build \\ %__MODULE__{}, attrs) do
    attrs
    |> normalize_datetime_attr(:inserted_at)
    |> normalize_enum_attr(:status, @status_values, %{
      0 => "success",
      1 => "failure"
    })
    |> normalize_enum_attr(:category, @category_values, %{
      0 => "clean",
      1 => "incremental"
    })
    |> normalize_enum_attr(:ci_provider, @ci_provider_values, @ci_provider_by_index)
    |> then(fn attrs ->
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
        :cacheable_tasks_count,
        :custom_tags,
        :custom_values
      ])
      |> validate_required([
        :id,
        :duration,
        :is_ci,
        :project_id,
        :account_id,
        :status
      ])
      |> validate_inclusion(:status, @status_values)
      |> validate_inclusion(:category, @category_values)
      |> validate_inclusion(:ci_provider, @ci_provider_values)
      |> validate_custom_tags()
      |> validate_custom_values()
    end)
  end

  defp normalize_datetime_attr(attrs, field) do
    case Map.fetch(attrs, field) do
      :error ->
        attrs

      {:ok, %DateTime{} = dt} ->
        Map.put(attrs, field, DateTime.to_naive(dt))

      {:ok, _} ->
        attrs
    end
  end

  defp normalize_enum_attr(attrs, field, allowed_values, by_index) do
    case Map.fetch(attrs, field) do
      :error ->
        attrs

      {:ok, nil} ->
        attrs

      {:ok, value} ->
        normalized = coerce_enum_value(value, allowed_values, by_index)
        if normalized == value, do: attrs, else: Map.put(attrs, field, normalized)
    end
  end

  defp coerce_enum_value(value, allowed_values, by_index) when is_atom(value) do
    value |> Atom.to_string() |> coerce_enum_value(allowed_values, by_index)
  end

  defp coerce_enum_value(value, _allowed_values, by_index) when is_integer(value) do
    Map.get(by_index, value) || Integer.to_string(value)
  end

  defp coerce_enum_value(value, allowed_values, _by_index) when is_binary(value) do
    if value in allowed_values, do: value
  end

  defp coerce_enum_value(_value, _allowed_values, _by_index), do: nil

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

  def normalize_enums(nil), do: nil

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

  defp status_string_to_atom(unknown) do
    require Logger

    Logger.warning("Unknown build status encountered: #{inspect(unknown)}, defaulting to :success")
    :success
  end

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

  defp validate_custom_tags(changeset) do
    changeset
    |> validate_length(:custom_tags, max: 50, message: "cannot have more than 50 tags")
    |> validate_change(:custom_tags, fn :custom_tags, tags ->
      Enum.flat_map(tags, fn tag ->
        cond do
          String.length(tag) > 50 ->
            [{:custom_tags, "tag exceeds maximum length of 50 characters"}]

          not Regex.match?(~r/^[a-zA-Z0-9_-]+$/, tag) ->
            [{:custom_tags, "tag contains invalid characters (only alphanumeric, hyphens, and underscores allowed)"}]

          true ->
            []
        end
      end)
    end)
  end

  defp validate_custom_values(changeset) do
    validate_change(changeset, :custom_values, fn :custom_values, values ->
      if map_size(values) > 20 do
        [{:custom_values, "cannot have more than 20 key-value pairs"}]
      else
        Enum.flat_map(values, fn {key, value} ->
          key_errors =
            cond do
              not is_binary(key) ->
                [{:custom_values, "keys must be strings"}]

              String.length(key) > 50 ->
                [{:custom_values, "key '#{String.slice(key, 0, 20)}...' exceeds maximum length of 50 characters"}]

              true ->
                []
            end

          value_errors =
            cond do
              not is_binary(value) ->
                [{:custom_values, "values must be strings"}]

              String.length(value) > 500 ->
                [{:custom_values, "value for key '#{key}' exceeds maximum length of 500 characters"}]

              true ->
                []
            end

          key_errors ++ value_errors
        end)
      end
    end)
  end
end
