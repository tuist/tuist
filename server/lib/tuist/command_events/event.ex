defmodule Tuist.CommandEvents.Event do
  @moduledoc false

  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :project_id,
      :name,
      :git_commit_sha,
      :git_ref,
      :git_branch,
      :status,
      :is_ci,
      :user_id,
      :hit_rate,
      :cacheable_targets_count,
      :cache_endpoint
    ],
    sortable: [:created_at, :ran_at, :duration, :hit_rate]
  }

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "command_events" do
    field :legacy_id, Ch, type: "UInt64"
    field :name, Ch, type: "String"
    field :subcommand, Ch, type: "Nullable(String)"
    field :command_arguments, Ch, type: "Nullable(String)"
    field :duration, Ch, type: "Int32"
    field :client_id, Ch, type: "String"
    field :tuist_version, Ch, type: "String"
    field :swift_version, Ch, type: "String"
    field :macos_version, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :is_ci, Ch, type: "Bool", default: false
    field :status, Ch, type: "Nullable(Int32)", default: 0
    field :error_message, Ch, type: "Nullable(String)"
    field :cacheable_targets, {:array, :string}, default: []
    field :local_cache_target_hits, {:array, :string}, default: []
    field :remote_cache_target_hits, {:array, :string}, default: []
    field :test_targets, {:array, :string}, default: []
    field :local_test_target_hits, {:array, :string}, default: []
    field :remote_test_target_hits, {:array, :string}, default: []
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :user_id, Ch, type: "Nullable(Int32)"
    field :preview_id, Ch, type: "Nullable(UUID)"
    field :build_run_id, Ch, type: "Nullable(UUID)"
    field :test_run_id, Ch, type: "Nullable(UUID)"
    field :cache_endpoint, Ch, type: "String", default: ""

    # When the command was run - provided by the CLI, defaulting to current server time when missing.
    field :ran_at, Ch, type: "DateTime64(6)"
    # Database timestamps defaulting to current server time on insertion or update.
    field :created_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"

    field :cacheable_targets_count, Ch, type: "UInt32", default: :database
    field :local_cache_hits_count, Ch, type: "UInt32", default: :database
    field :remote_cache_hits_count, Ch, type: "UInt32", default: :database
    field :test_targets_count, Ch, type: "UInt32", default: :database
    field :local_test_hits_count, Ch, type: "UInt32", default: :database
    field :remote_test_hits_count, Ch, type: "UInt32", default: :database
    field :hit_rate, Ch, type: "Nullable(Float32)", default: :database

    belongs_to :project, Tuist.Projects.Project, define_field: false
    belongs_to :user, Tuist.Accounts.User, define_field: false

    has_many :xcode_targets, Tuist.Xcode.XcodeTarget,
      foreign_key: :command_event_id,
      references: :id

    field :user_account_name, :string, virtual: true
  end

  def changeset(event_attrs) do
    id = UUIDv7.generate()

    event_attrs =
      event_attrs
      |> Map.put_new(:id, id)
      |> Map.put(:legacy_id, Tuist.UUIDv7.to_int64(id))
      |> normalize_status()
      |> Map.update(:command_arguments, "", fn
        args when is_list(args) -> Enum.join(args, " ")
        args when is_binary(args) -> args
        nil -> ""
        _ -> ""
      end)
      |> Map.put_new(:updated_at, Map.get(event_attrs, :created_at))
      |> convert_datetime_field(:ran_at)
      |> convert_datetime_field(:created_at)
      |> convert_datetime_field(:updated_at)

    event_attrs
  end

  defp normalize_status(attrs) do
    if Map.has_key?(attrs, :status) do
      Map.update!(attrs, :status, fn
        :success -> 0
        :failure -> 1
        "success" -> 0
        "failure" -> 1
        other -> other
      end)
    else
      attrs
    end
  end

  defp convert_datetime_field(attrs, field) do
    case Map.get(attrs, field) do
      %DateTime{} = dt ->
        update_field_with_naive_datetime(attrs, field, DateTime.to_naive(dt))

      %NaiveDateTime{} = ndt ->
        update_field_with_naive_datetime(attrs, field, ndt)

      str when is_binary(str) ->
        ndt = parse_datetime_string(str)
        update_field_with_naive_datetime(attrs, field, ndt)

      nil ->
        attrs

      _ ->
        attrs
    end
  end

  defp parse_datetime_string(str) do
    cond do
      String.contains?(str, "Z") or String.contains?(str, "+") ->
        {:ok, dt, _offset} = DateTime.from_iso8601(str)
        DateTime.to_naive(dt)

      String.contains?(str, " ") ->
        # Already in NaiveDateTime format
        {:ok, parsed} = NaiveDateTime.from_iso8601(String.replace(str, " ", "T"))
        parsed

      true ->
        {:ok, dt, _offset} = DateTime.from_iso8601(str <> "Z")
        DateTime.to_naive(dt)
    end
  end

  defp update_field_with_naive_datetime(attrs, field, ndt) do
    ndt_with_usec = %{ndt | microsecond: {elem(ndt.microsecond, 0), 6}}
    Map.put(attrs, field, ndt_with_usec)
  end

  def normalize_enums(event) do
    %{
      event
      | status: status_int_to_atom(event.status)
    }
  end

  defp status_int_to_atom(0), do: :success
  defp status_int_to_atom(1), do: :failure
  defp status_int_to_atom(_), do: :success
end
