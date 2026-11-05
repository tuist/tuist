defmodule Pulse.Traces.SearchExpression do
  @moduledoc """
  Bounded TraceQL for retained-context search, not discovery or window search:
  same-span boolean spansets, optionally joined by the structural operators
  `>>`, `>`, `<<`, `<` and `~`, and an optional `| select(...)`.

  The wire program is a flat list of `{scope, key, op, value}` strings: each
  spanset's postfix instructions, `{"spanset", "", op, ""}` between spansets,
  then `{"select", scope, key, ""}` entries.
  """

  alias Pulse.Codec.NIF

  @word ~r/\A[A-Za-z0-9_.:µ-]+/u
  @attribute ~r/\A(resource|span|event)?\.([A-Za-z_][A-Za-z0-9_.-]*)\z/
  @select ~r/\A(?:(resource|span|event)?\.([A-Za-z_][A-Za-z0-9_.-]*)|(?:span:)?(name|status|kind))\z/
  @relations [">>", "<<", ">", "<", "~"]
  @string_scopes ["resource.string", "span.string", "none.string", "event.string"]
  @int_scopes ["resource.int", "span.int", "none.int", "event.int", "intrinsic"]
  @hint ~r/\Awith\s*\(\s*most_recent\s*=\s*true\s*\)\s*\z/
  @comparisons ~w(= != < <= > >=)
  @max_int 9_223_372_036_854_775_807

  def parse(query) when is_binary(query) and byte_size(query) <= 16_384 do
    with true <- String.valid?(query),
         {:ok, program, tail} <- spansets(String.trim_leading(query), []),
         {:ok, select, tail} <- pipeline(String.trim_leading(tail)),
         true <- String.trim(tail) == "" or Regex.match?(@hint, String.trim_leading(tail)),
         program = program ++ select,
         :ok <- validate(program) do
      {:ok, {:expression, program}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  def parse(_), do: {:error, :query_expression_limit}

  defp spansets(<<"{", rest::binary>>, acc) do
    with {:ok, tokens, tail} <- tokens(rest, []),
         {:ok, program, []} <- expression(tokens, 0) do
      tail = String.trim_leading(tail)

      case Enum.find(@relations, &String.starts_with?(tail, &1)) do
        nil ->
          {:ok, acc ++ program, tail}

        op ->
          next = String.trim_leading(binary_part(tail, byte_size(op), byte_size(tail) - byte_size(op)))
          spansets(next, acc ++ program ++ [{"spanset", "", op, ""}])
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp spansets(_, _), do: {:error, :unsupported_trace_selector}

  defp pipeline(<<"|", rest::binary>>) do
    with [whole, list] <- Regex.run(~r/\A\s*select\s*\(([^()]*)\)/, rest),
         {:ok, select} <- select(String.split(list, ",")) do
      {:ok, select, binary_part(rest, byte_size(whole), byte_size(rest) - byte_size(whole))}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp pipeline(tail), do: {:ok, [], tail}

  defp select(names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      case Regex.run(@select, String.trim(name)) do
        [_, scope, key] -> {:cont, {:ok, [{"select", if(scope == "", do: "none", else: scope), key, ""} | acc]}}
        [_, "", "", intrinsic] -> {:cont, {:ok, [{"select", "intrinsic", intrinsic, ""} | acc]}}
        _ -> {:halt, {:error, :unsupported_trace_selector}}
      end
    end)
    |> case do
      {:ok, select} -> {:ok, Enum.reverse(select)}
      error -> error
    end
  end

  defp tokens(_rest, acc) when length(acc) > 576, do: {:error, :query_expression_limit}

  defp tokens(rest, acc) do
    case String.trim_leading(rest) do
      <<"}", tail::binary>> ->
        {:ok, Enum.reverse(acc), tail}

      <<"\"", tail::binary>> = input ->
        with {:ok, size} <- string_end(tail, 1, false),
             {:ok, value} <- Pulse.JSON.decode(binary_part(input, 0, size)) do
          tokens(binary_part(input, size, byte_size(input) - size), [{:string, value} | acc])
        else
          _ -> {:error, :unsupported_trace_selector}
        end

      input ->
        token(input, acc)
    end
  end

  defp token(input, acc) do
    operator =
      Enum.find(["&&", "||", "!=", "!~", "=~", "<=", ">=", "=", "<", ">", "(", ")"], &String.starts_with?(input, &1))

    cond do
      operator ->
        tokens(binary_part(input, byte_size(operator), byte_size(input) - byte_size(operator)), [operator | acc])

      word = Regex.run(@word, input) ->
        [word] = word
        tokens(binary_part(input, byte_size(word), byte_size(input) - byte_size(word)), [{:word, word} | acc])

      true ->
        {:error, :unsupported_trace_selector}
    end
  end

  defp string_end(<<>>, _, _), do: :error
  defp string_end(<<"\"", _::binary>>, size, false), do: {:ok, size + 1}
  defp string_end(<<"\\", rest::binary>>, size, false), do: string_end(rest, size + 1, true)
  defp string_end(<<_, rest::binary>>, size, _), do: string_end(rest, size + 1, false)

  defp expression(tokens, depth) do
    with {:ok, lhs, rest} <- primary(tokens, depth), do: combine(rest, lhs, depth)
  end

  # TraceQL gives && and || the same precedence, unlike many languages.
  defp combine([op | rest], lhs, depth) when op in ["&&", "||"] do
    with {:ok, rhs, tail} <- primary(rest, depth), do: combine(tail, lhs ++ rhs ++ [{"boolean", "", op, ""}], depth)
  end

  defp combine(rest, lhs, _depth), do: {:ok, lhs, rest}
  defp primary(_, depth) when depth > 16, do: {:error, :query_expression_limit}

  defp primary(["(" | rest], depth) do
    case expression(rest, depth + 1) do
      {:ok, program, [")" | tail]} -> {:ok, program, tail}
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp primary([{:word, field}, op, literal | rest], _depth) do
    with {:ok, predicate} <- predicate(field, op, literal), do: {:ok, [predicate], rest}
  end

  defp primary(_, _), do: {:error, :unsupported_trace_selector}

  defp predicate(field, op, {:string, value}) when op in ["=", "!=", "=~", "!~"] do
    case Regex.run(@attribute, field) do
      [_, scope, key] -> {:ok, {if(scope == "", do: "none", else: scope) <> ".string", key, op, value}}
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp predicate(field, op, {:word, value}) when op in @comparisons do
    cond do
      field in ["status", "span:status"] and value in ~w(unset ok error) and op in ["=", "!="] ->
        {:ok, {"intrinsic", "status", op, Integer.to_string(Enum.find_index(~w(unset ok error), &(&1 == value)))}}

      field in ["duration", "span:duration"] ->
        with {:ok, ns} <- duration(value), do: {:ok, {"intrinsic", "duration", op, Integer.to_string(ns)}}

      true ->
        numeric_predicate(field, op, value)
    end
  end

  defp predicate(_, _, _), do: {:error, :unsupported_trace_selector}

  defp numeric_predicate(field, op, value) do
    with [_, scope, key] <- Regex.run(@attribute, field),
         {number, ""} when number >= -@max_int - 1 and number <= @max_int <- Integer.parse(value) do
      {:ok, {if(scope == "", do: "none", else: scope) <> ".int", key, op, Integer.to_string(number)}}
    else
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  @doc "Nanoseconds of a Go `time.ParseDuration` spelling such as `1m30s`."
  def go_duration(value) when is_binary(value), do: duration(value)

  defp duration(value) when byte_size(value) in 1..128, do: duration(value, 0)
  defp duration(_), do: {:error, :unsupported_trace_selector}
  defp duration("", total), do: {:ok, total}

  defp duration(value, total) do
    with [prefix, number, unit] <- Regex.run(~r/\A([0-9]+(?:\.[0-9]+)?)(ns|us|µs|ms|s|m|h)/u, value),
         parts = String.split(number, "."),
         multiplier =
           Map.fetch!(
             %{
               "ns" => 1,
               "us" => 1000,
               "µs" => 1000,
               "ms" => 1_000_000,
               "s" => 1_000_000_000,
               "m" => 60_000_000_000,
               "h" => 3_600_000_000_000
             },
             unit
           ),
         total = total + component(parts, multiplier),
         true <- total <= @max_int do
      duration(binary_part(value, byte_size(prefix), byte_size(value) - byte_size(prefix)), total)
    else
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  # Match Go time.ParseDuration's bounded leading fraction and IEEE rounding.
  # Subsequent comparisons are exact int64 nanoseconds, never float comparisons.
  defp component([whole], unit), do: String.to_integer(whole) * unit

  defp component([whole, fraction], unit) do
    {numerator, scale} = fraction_digits(fraction, 0, 1.0)
    String.to_integer(whole) * unit + trunc(numerator * (unit / scale))
  end

  defp fraction_digits(<<>>, number, scale), do: {number, scale}

  defp fraction_digits(<<digit, rest::binary>>, number, scale) do
    next = number * 10 + digit - ?0

    if number > div(@max_int, 10) or next > @max_int + 1,
      do: {number, scale},
      else: fraction_digits(rest, next, scale * 10.0)
  end

  @doc false
  def validate(program) when is_list(program) and length(program) in 1..64 do
    with true <- Enum.all?(program, &wire_instruction?/1),
         {:ok, {spansets, _relations, select}} <- split(program),
         true <- Enum.all?(select, &valid_select?/1) do
      if length(spansets) > 4 or length(select) > 8 or Enum.any?(spansets, &(length(&1) > 31)),
        do: {:error, :query_expression_limit},
        else: validate_instructions(spansets)
    else
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  def validate(_), do: {:error, :query_expression_limit}

  defp wire_instruction?({scope, key, op, value}),
    do: Enum.all?([scope, key, op, value], &(is_binary(&1) and String.valid?(&1)))

  defp wire_instruction?(_), do: false

  @doc "Spanset programs, the relations between them and the select list of a wire program."
  def split(program) do
    {spansets, select} = Enum.split_while(program, &(not match?({"select", _, _, _}, &1)))

    with true <- Enum.all?(select, &match?({"select", _, _, _}, &1)),
         {spansets, relations} <- chunks(spansets, [], [], []),
         true <- Enum.all?(relations, &(&1 in @relations)) do
      {:ok, {spansets, relations, select}}
    else
      _ -> :error
    end
  end

  defp chunks([], current, spansets, relations),
    do: {Enum.reverse([Enum.reverse(current) | spansets]), Enum.reverse(relations)}

  defp chunks([{"spanset", "", op, ""} | rest], current, spansets, relations) when current != [],
    do: chunks(rest, [], [Enum.reverse(current) | spansets], [op | relations])

  defp chunks([{"spanset", _, _, _} | _], _, _, _), do: :error
  defp chunks([leaf | rest], current, spansets, relations), do: chunks(rest, [leaf | current], spansets, relations)

  @doc "Whether the program needs event, structural or select support beyond the same-span grammar."
  def extended?(program) do
    Enum.any?(program, fn {scope, _, _, _} -> scope in ["spanset", "select"] or String.starts_with?(scope, "event.") end)
  end

  defp valid_select?({"select", scope, key, ""}) when scope in ["resource", "span", "event", "none"],
    do: byte_size(key) in 1..256

  defp valid_select?({"select", "intrinsic", key, ""}), do: key in ["name", "status", "kind"]
  defp valid_select?(_), do: false

  defp validate_instructions(spansets) do
    program = Enum.concat(spansets)
    leaves = Enum.reject(program, &match?({"boolean", _, _, _}, &1))

    cond do
      length(leaves) > 16 or Enum.count(leaves, fn {_, _, op, _} -> op in ["=~", "!~"] end) > 8 ->
        {:error, :query_expression_limit}

      Enum.any?(leaves, fn {_, _, _, value} -> String.contains?(value, "${") end) ->
        {:error, :unexpanded_trace_variable}

      not Enum.all?(leaves, &valid_leaf?/1) ->
        {:error, :unsupported_trace_selector}

      Enum.any?(spansets, &(stack_size(&1, 0) != 1)) ->
        {:error, :unsupported_trace_selector}

      true ->
        :ok
    end
  end

  defp stack_size([], size), do: size

  defp stack_size([{"boolean", "", op, ""} | rest], size) when op in ["&&", "||"] and size >= 2,
    do: stack_size(rest, size - 1)

  defp stack_size([{"boolean", _, _, _} | _], _), do: -1
  defp stack_size([_ | rest], size), do: stack_size(rest, size + 1)

  defp valid_leaf?({scope, key, op, value}) when scope in @string_scopes do
    byte_size(key) in 1..256 and byte_size(value) <= 4096 and
      (op in ["=", "!="] or
         (op in ["=~", "!~"] and byte_size(value) <= 1024 and
            NIF.validate_metric_regex(value) == :ok and NIF.validate_metric_regex(Pulse.QueryRegex.anchor(value)) == :ok))
  end

  defp valid_leaf?({scope, key, op, value}) when scope in @int_scopes do
    byte_size(key) in 1..256 and byte_size(value) <= 20 and op in @comparisons and valid_integer?(scope, key, op, value)
  end

  defp valid_leaf?(_), do: false

  defp valid_integer?(scope, key, op, value) do
    case Integer.parse(value) do
      {number, ""} when number >= -@max_int - 1 and number <= @max_int ->
        case {scope, key} do
          {"intrinsic", "status"} -> number in 0..2 and op in ["=", "!="]
          {"intrinsic", "duration"} -> number >= 0
          {"intrinsic", _} -> false
          _ -> true
        end

      _ ->
        false
    end
  end
end
