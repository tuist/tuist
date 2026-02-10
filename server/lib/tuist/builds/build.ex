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
    field :status, Ch, type: "LowCardinality(String)"
    field :category, Ch, type: "LowCardinality(String)"
    field :configuration, Ch, type: "Nullable(String)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :ci_run_id, Ch, type: "Nullable(String)"
    field :ci_project_handle, Ch, type: "Nullable(String)"
    field :ci_host, Ch, type: "Nullable(String)"

    field :ci_provider, Ch, type: "LowCardinality(String)"

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
    |> default_to_empty_string([:status, :category, :ci_provider])
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
      |> validate_inclusion(:status, ["" | @status_values])
      |> validate_inclusion(:category, ["" | @category_values])
      |> validate_inclusion(:ci_provider, ["" | @ci_provider_values])
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

  defp default_to_empty_string(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      case Map.fetch(acc, field) do
        {:ok, nil} -> Map.put(acc, field, "")
        {:ok, value} when is_atom(value) -> Map.put(acc, field, Atom.to_string(value))
        :error -> Map.put(acc, field, "")
        _ -> acc
      end
    end)
  end

  def to_buffer_map(%__MODULE__{} = build) do
    build
    |> Map.from_struct()
    |> Map.drop([:__meta__, :project, :ran_by_account, :issues, :files, :targets])
    |> Map.update(:id, UUIDv7.generate(), fn id -> id || UUIDv7.generate() end)
    |> Map.update(:inserted_at, NaiveDateTime.utc_now(), fn
      nil -> NaiveDateTime.utc_now()
      %DateTime{} = dt -> DateTime.to_naive(dt)
      other -> other
    end)
    |> Map.new(fn
      {key, %NaiveDateTime{} = ndt} -> {key, %{ndt | microsecond: {elem(ndt.microsecond, 0), 6}}}
      other -> other
    end)
  end

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
