defmodule Tuist.QA.Log do
  @moduledoc false

  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :qa_run_id,
      :type,
      :timestamp
    ],
    sortable: [:timestamp, :inserted_at]
  }

  @primary_key false
  schema "qa_logs" do
    field :project_id, Ch, type: "Int64"
    field :qa_run_id, Ch, type: "UUID"
    field :data, Ch, type: "String"
    field :type, Ch, type: "Enum8('usage' = 0, 'tool_call' = 1, 'tool_call_result' = 2, 'message' = 3)"
    field :timestamp, Ch, type: "DateTime"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(log_attrs) do
    log_attrs
    |> convert_datetime_field(:timestamp)
    |> convert_datetime_field(:inserted_at)
    |> normalize_type()
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
        case DateTime.from_iso8601(str) do
          {:ok, dt, _offset} -> DateTime.to_naive(dt)
          {:error, _} -> fallback_datetime()
        end

      String.contains?(str, " ") ->
        case NaiveDateTime.from_iso8601(String.replace(str, " ", "T")) do
          {:ok, parsed} -> parsed
          {:error, _} -> fallback_datetime()
        end

      true ->
        case DateTime.from_iso8601(str <> "Z") do
          {:ok, dt, _offset} -> DateTime.to_naive(dt)
          {:error, _} -> fallback_datetime()
        end
    end
  end

  defp fallback_datetime do
    DateTime.to_naive(DateTime.utc_now())
  end

  defp update_field_with_naive_datetime(attrs, field, ndt) do
    ndt_with_usec = %{ndt | microsecond: {elem(ndt.microsecond, 0), 6}}
    Map.put(attrs, field, ndt_with_usec)
  end

  defp normalize_type(attrs) do
    if Map.has_key?(attrs, :type) do
      Map.update!(attrs, :type, fn
        "usage" -> 0
        "tool_call" -> 1
        "tool_call_result" -> 2
        "message" -> 3
        type when is_integer(type) -> type
        _ -> 3
      end)
    else
      attrs
    end
  end

  def normalize_enums(log) do
    %{
      log
      | type: String.to_atom(log.type)
    }
  end
end
