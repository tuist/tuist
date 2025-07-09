defmodule Tuist.CommandEvents.Clickhouse.Event do
  @moduledoc ~S"""
  ClickHouse schema for command events.
  """
  use Ecto.Schema

  import Ecto.Query

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
      :user_id
    ],
    sortable: [:created_at, :ran_at, :duration]
  }

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "command_events" do
    field :legacy_id, Ch, type: "UInt64"
    field :legacy_artifact_path, :boolean, default: false
    field :name, :string
    field :subcommand, :string
    field :command_arguments, :string
    field :duration, Ch, type: "Int32"
    field :client_id, :string
    field :tuist_version, :string
    field :swift_version, :string
    field :macos_version, :string
    field :project_id, Ch, type: "Int64"
    field :is_ci, :boolean, default: false
    field :status, Ch, type: "Int32", default: 0
    field :error_message, :string
    field :cacheable_targets, {:array, :string}, default: []
    field :local_cache_target_hits, {:array, :string}, default: []
    field :remote_cache_target_hits, {:array, :string}, default: []
    field :remote_cache_target_hits_count, Ch, type: "Int32", default: 0
    field :test_targets, {:array, :string}, default: []
    field :local_test_target_hits, {:array, :string}, default: []
    field :remote_test_target_hits, {:array, :string}, default: []
    field :remote_test_target_hits_count, Ch, type: "Int32", default: 0
    field :git_commit_sha, :string
    field :git_ref, :string
    field :git_branch, :string
    field :user_id, Ch, type: "Int32"
    field :preview_id, Ecto.UUID
    field :build_run_id, Ecto.UUID
    field :ran_at, Ch, type: "DateTime64(6)"
    field :created_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"
    field :hit_rate, :float, virtual: true
  end

  def with_hit_rate(query) do
    from e in query,
      select_merge: %{
        hit_rate:
          fragment(
            "CASE WHEN length(?) > 0 THEN (length(?) + length(?))::float / length(?) * 100 ELSE NULL END",
            e.cacheable_targets,
            e.local_cache_target_hits,
            e.remote_cache_target_hits,
            e.cacheable_targets
          )
      }
  end

  def changeset(event_attrs) do
    event_attrs =
      event_attrs
      |> Map.put_new(:id, UUIDv7.generate())
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
