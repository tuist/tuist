defmodule Pulse.Traces.Selector do
  @moduledoc "Bounded single-spanset string-selector syntax. Unsupported TraceQL is rejected, never approximated."

  alias Pulse.Codec.NIF

  @identifier ~r/\A(resource|span)\.([A-Za-z_][A-Za-z0-9_.-]*)/
  @hint ~r/\Awith\s*\(\s*most_recent\s*=\s*true\s*\)\s*\z/

  def parse(query) when is_binary(query) and byte_size(query) <= 16_384 do
    with true <- String.valid?(query),
         <<"{", rest::binary>> <- trim(query),
         {:ok, predicates, rest} <- predicates(trim(rest), []),
         true <- trim(rest) == "" or Regex.match?(@hint, trim(rest)),
         :ok <- validate(predicates) do
      {:ok, predicates}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  def parse(_query), do: {:error, :query_expression_limit}

  defp predicates(_rest, acc) when length(acc) == 16, do: {:error, :query_expression_limit}

  defp predicates(rest, acc) do
    with [prefix, scope, key] <- Regex.run(@identifier, rest),
         after_key = binary_part(rest, byte_size(prefix), byte_size(rest) - byte_size(prefix)),
         {:ok, op, after_op} <- operator(trim(after_key)),
         {:ok, value, tail} <- literal(trim(after_op)) do
      predicate = {scope, key, op, value}

      case trim(tail) do
        <<"}", tail::binary>> -> {:ok, Enum.reverse([predicate | acc]), tail}
        <<"&&", tail::binary>> -> predicates(trim(tail), [predicate | acc])
        _ -> {:error, :unsupported_trace_selector}
      end
    else
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp operator(<<"=~", rest::binary>>), do: {:ok, "=~", rest}
  defp operator(<<"=", rest::binary>>), do: {:ok, "=", rest}
  defp operator(_), do: :error

  defp literal(<<"\"", rest::binary>> = input) do
    with {:ok, length} <- string_end(rest, 1, false),
         {:ok, value} when is_binary(value) <- Pulse.JSON.decode(binary_part(input, 0, length)) do
      {:ok, value, binary_part(input, length, byte_size(input) - length)}
    else
      _ -> :error
    end
  end

  defp literal(_), do: :error
  defp string_end(<<>>, _length, _escaped), do: :error
  defp string_end(<<"\"", _rest::binary>>, length, false), do: {:ok, length + 1}
  defp string_end(<<"\\", rest::binary>>, length, false), do: string_end(rest, length + 1, true)
  defp string_end(<<_byte, rest::binary>>, length, _escaped), do: string_end(rest, length + 1, false)
  defp trim(value), do: String.trim_leading(value)

  defp validate(predicates) do
    cond do
      Enum.any?(predicates, fn {_, _, _, value} -> String.contains?(value, "${") end) ->
        {:error, :unexpanded_trace_variable}

      Enum.count(predicates, fn {_, _, op, _} -> op == "=~" end) > 8 ->
        {:error, :query_expression_limit}

      Enum.all?(predicates, &valid_predicate?/1) ->
        :ok

      true ->
        {:error, :unsupported_trace_selector}
    end
  end

  defp valid_predicate?({_, key, "=", value}), do: byte_size(key) <= 256 and byte_size(value) <= 4096

  defp valid_predicate?({_, key, "=~", value}) do
    byte_size(key) <= 256 and byte_size(value) <= 1024 and NIF.validate_metric_regex(value) == :ok and
      NIF.validate_metric_regex(Pulse.QueryRegex.anchor(value)) == :ok
  end
end
