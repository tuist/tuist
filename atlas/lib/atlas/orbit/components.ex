defmodule Atlas.Orbit.Components do
  @moduledoc """
  Versioned, data-only cards projected from the already-redacted durable tool
  rendering. No raw model result, executable UI, URLs or new permissions cross
  this boundary. Older clients continue to use tool_output.
  """

  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Rendering

  def for_message(%Message{kind: "tool", tool_status: "succeeded", tool_output: output} = message)
      when is_binary(output) and byte_size(output) <= 16_000 do
    with {:ok, value} <- JSON.decode(output),
         {columns, rows} when columns != [] and rows != [] <- table(Rendering.redact(value)) do
      %{
        type: "result_table",
        version: 1,
        data: %{title: Rendering.truncate(message.tool_name || "Tool result", 120), columns: columns, rows: rows},
        actions: [%{id: "show_evidence", label: "View source"}],
        fallback: Rendering.truncate(Rendering.output(value), 4_000)
      }
    else
      _ -> nil
    end
  end

  def for_message(_message), do: nil

  defp table(value) when is_map(value) do
    # MCP list tools commonly wrap their rows in a named collection.
    collection =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.find_value(fn {_key, inner} -> if is_list(inner) and inner != [], do: inner end)

    if collection do
      table(collection)
    else
      rows =
        value |> Enum.sort_by(&elem(&1, 0)) |> Enum.take(5) |> Enum.map(fn {key, inner} -> [cell(key), cell(inner)] end)

      {["Field", "Value"], rows}
    end
  end

  defp table([first | _] = values) when is_map(first) do
    columns = first |> Map.keys() |> Enum.sort() |> Enum.take(3)

    rows =
      values
      |> Enum.filter(&is_map/1)
      |> Enum.take(5)
      |> Enum.map(fn row -> Enum.map(columns, &cell(Map.get(row, &1))) end)

    {Enum.map(columns, &cell/1), rows}
  end

  defp table(values) when is_list(values), do: {["Value"], values |> Enum.take(5) |> Enum.map(&[cell(&1)])}
  defp table(_value), do: nil

  defp cell(value) when is_binary(value), do: Rendering.truncate(value, 160)
  defp cell(value), do: value |> JSON.encode!() |> Rendering.truncate(160)
end
