defmodule Tuist.QA.Log do
  @moduledoc false

  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :qa_run_id,
      :level,
      :timestamp
    ],
    sortable: [:timestamp, :inserted_at]
  }

  @primary_key false
  schema "qa_logs" do
    field :project_id, Ch, type: "Int64"
    field :qa_run_id, Ch, type: "UUID"
    field :message, Ch, type: "String"
    field :level, Ch, type: "Enum8('debug' = 0, 'info' = 1, 'warning' = 2, 'error' = 3)"
    field :timestamp, Ch, type: "DateTime"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(log_attrs) do
    log_attrs
    |> convert_datetime_field(:timestamp)
    |> convert_datetime_field(:inserted_at)
    |> normalize_level()
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

  defp normalize_level(attrs) do
    if Map.has_key?(attrs, :level) do
      Map.update!(attrs, :level, fn
        "debug" -> 0
        "info" -> 1
        "warning" -> 2
        "error" -> 3
        level when is_integer(level) -> level
        _ -> 1
      end)
    else
      attrs
    end
  end

  def normalize_enums(log) do
    %{
      log
      | level: level_int_to_atom(log.level)
    }
  end

  defp level_int_to_atom(0), do: :debug
  defp level_int_to_atom(1), do: :info
  defp level_int_to_atom(2), do: :warning
  defp level_int_to_atom(3), do: :error
  defp level_int_to_atom(_), do: :info
end
