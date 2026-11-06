defmodule Pulse.LogQL.Limits do
  @moduledoc false
  def input(text) when is_binary(text) and byte_size(text) in 1..16_384, do: scan(text, nil, 0, 0)
  def input(_), do: {:error, :query_expression_limit}
  defp scan(_, _, depth, operators) when depth > 64 or operators > 512, do: {:error, :query_expression_limit}
  defp scan(<<>>, _, _, _), do: :ok
  defp scan(<<92, _, rest::binary>>, 34, depth, ops), do: scan(rest, 34, depth, ops)
  defp scan(<<char, rest::binary>>, quote, depth, ops) when char == quote, do: scan(rest, nil, depth, ops)
  defp scan(<<_, rest::binary>>, quote, depth, ops) when not is_nil(quote), do: scan(rest, quote, depth, ops)
  defp scan(<<char, rest::binary>>, _, depth, ops) when char in [34, 96], do: scan(rest, char, depth, ops)
  defp scan(<<40, rest::binary>>, _, depth, ops), do: scan(rest, nil, depth + 1, ops)
  defp scan(<<41, rest::binary>>, _, depth, ops), do: scan(rest, nil, max(0, depth - 1), ops)
  defp scan(<<char, rest::binary>>, _, depth, ops) when char in ~c"|+-*/%<>=&!", do: scan(rest, nil, depth, ops + 1)
  defp scan(<<_, rest::binary>>, _, depth, ops), do: scan(rest, nil, depth, ops)

  def ast(ast) do
    case walk(ast, 0, 0) do
      {:ok, count} when count <= 256 -> :ok
      _ -> {:error, :query_expression_limit}
    end
  end

  defp walk(_, count, depth) when count > 256 or depth > 64, do: :error

  defp walk(value, count, depth) when is_map(value),
    do: children(Map.values(Map.delete(value, :__struct__)), count + 1, depth)

  defp walk(value, count, depth) when is_tuple(value), do: children(Tuple.to_list(value), count + 1, depth)
  defp walk(value, count, depth) when is_list(value), do: children(value, count, depth)
  defp walk(_, count, _), do: {:ok, count}

  defp children(values, count, depth) do
    Enum.reduce_while(values, {:ok, count}, fn value, {:ok, used} ->
      case walk(value, used, depth + 1) do
        {:ok, used} -> {:cont, {:ok, used}}
        _ -> {:halt, :error}
      end
    end)
  end
end
