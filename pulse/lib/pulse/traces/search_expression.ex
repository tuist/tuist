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
  @float ~r/\A-?(?:[0-9]+\.[0-9]*|\.[0-9]+|[0-9]+[eE][+-]?[0-9]+)(?:[eE][+-]?[0-9]+)?\z/
  @relations [">>", "<<", ">", "<", "~"]
  @owners ~w(resource span none event link instrumentation)
  @string_intrinsics ~w(name statusMessage rootName rootServiceName span:id span:parentID trace:id event:name link:traceID link:spanID instrumentation:name instrumentation:version)
  @intrinsics @string_intrinsics ++ ~w(status kind duration trace_duration event:timeSinceStart)
  @aliases %{
    "span:name" => "name",
    "span:statusMessage" => "statusMessage",
    "trace:rootName" => "rootName",
    "trace:rootService" => "rootServiceName",
    "span:status" => "status",
    "span:kind" => "kind",
    "span:duration" => "duration",
    "traceDuration" => "trace_duration",
    "trace:duration" => "trace_duration"
  }
  @string_scopes Enum.map(@owners, &(&1 <> ".string")) ++ ["intrinsic.string"]
  @int_scopes Enum.map(@owners, &(&1 <> ".int")) ++ ["intrinsic"]
  @float_scopes Enum.map(@owners, &(&1 <> ".float"))
  @bool_scopes Enum.map(@owners, &(&1 <> ".bool"))
  @any_scopes ~w(resource.any span.any none.any instrumentation.any)
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
         {:ok, program, []} <- spanset_expression(tokens) do
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

  defp spanset_expression([]), do: {:ok, [{"constant", "", "true", ""}], []}
  defp spanset_expression(tokens), do: expression(tokens, 0)

  defp pipeline(<<"|", rest::binary>>) do
    with [whole] <- Regex.run(~r/\A\s*select\s*\(/, rest),
         {:ok, names, tail} <- select_names(binary_part(rest, byte_size(whole), byte_size(rest) - byte_size(whole)), []),
         {:ok, select} <- select(names) do
      {:ok, select, tail}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp pipeline(tail), do: {:ok, [], tail}

  defp select_names(input, acc) do
    with {:ok, name, tail} <- identifier(String.trim_leading(input)) do
      tail = String.trim_leading(tail)

      case tail do
        <<",", rest::binary>> -> select_names(rest, [name | acc])
        <<")", rest::binary>> -> {:ok, Enum.reverse([name | acc]), rest}
        _ -> {:error, :unsupported_trace_selector}
      end
    end
  end

  defp select(names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      case field(name) do
        {:ok, scope, key} -> {:cont, {:ok, [{"select", scope, key, ""} | acc]}}
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

      Regex.match?(~r/\A(?:resource|span|event|link|instrumentation)?\./, input) and
          not Regex.match?(~r/\A\.[0-9]/, input) ->
        with {:ok, name, tail} <- identifier(input), do: tokens(tail, [{:word, name} | acc])

      word =
          Regex.run(~r/\A-?(?:[0-9]+\.[0-9]*|\.[0-9]+|[0-9]+)(?:[eE][+-]?[0-9]+)?(?=\s|[})<>=!&|]|\z)/, input) ||
            Regex.run(@word, input) ->
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

  # Tempo's attribute lexer concatenates quoted and unquoted segments. Only
  # quote and backslash escapes exist here; this is not the literal grammar.
  defp identifier(input), do: identifier(input, "", false)
  defp identifier(<<"\\", c, rest::binary>>, acc, true) when c in [?", ?\\], do: identifier(rest, acc <> <<c>>, true)
  defp identifier(<<"\\", _::binary>>, _acc, true), do: {:error, :unsupported_trace_selector}
  defp identifier(<<"\"", rest::binary>>, acc, quote), do: identifier(rest, acc, not quote)
  defp identifier(<<>>, _acc, true), do: {:error, :unsupported_trace_selector}
  defp identifier(<<>>, acc, false), do: {:ok, acc, ""}

  defp identifier(<<c::utf8, rest::binary>> = input, acc, quote) do
    if not quote and (c in ~c"{}()=~!<>&|^," or String.trim(<<c::utf8>>) == "") do
      if acc == "", do: {:error, :unsupported_trace_selector}, else: {:ok, acc, input}
    else
      identifier(rest, acc <> <<c::utf8>>, quote)
    end
  end

  # Identifiers have already been decoded by the lexer, never by a JSON
  # round trip (which would reinterpret escaped attribute-key bytes).
  defp field(name) do
    case Map.get(@aliases, name, name) do
      intrinsic when intrinsic in @intrinsics -> {:ok, "intrinsic", intrinsic}
      _ -> attribute_field(name)
    end
  end

  defp attribute_field(name) do
    case Regex.run(~r/\A(resource|span|event|link|instrumentation)?\.(.+)\z/us, name) do
      [_, "", key] -> {:ok, "none", key}
      [_, scope, key] -> {:ok, scope, key}
      _ -> {:error, :unsupported_trace_selector}
    end
  end

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

  # Grafana's Traces Drilldown combines `true` and `nestedSetParent<0` (root
  # spans: no parent ID, which span:parentID reports as zeros) with filters.
  defp primary([{:word, "true"} | rest], _depth) when rest == [] or hd(rest) in ["&&", "||", ")"],
    do: {:ok, [{"constant", "", "true", ""}], rest}

  defp primary([{:word, field}, "<", {:word, "0"} | rest], _depth)
       when field in ["nestedSetParent", "span:nestedSetParent"],
       do: {:ok, [{"intrinsic.string", "span:parentID", "=", "0000000000000000"}], rest}

  # `attr != nil` (present with any type) and `attr = nil` (absent).
  defp primary([{:word, field}, op, {:word, "nil"} | rest], _depth) when op in ["=", "!="] do
    case field(field) do
      {:ok, scope, key} when scope in ~w(resource span none instrumentation) ->
        {:ok, [{scope <> ".any", key, op, "nil"}], rest}

      _ ->
        {:error, :unsupported_trace_selector}
    end
  end

  defp primary([{:word, field}, op, literal | rest], _depth) do
    with {:ok, predicate} <- predicate(field, op, literal), do: {:ok, [predicate], rest}
  end

  defp primary(_, _), do: {:error, :unsupported_trace_selector}

  defp predicate(field, op, {:string, value}) when op in ["=", "!=", "=~", "!~"] do
    case field(field) do
      {:ok, "intrinsic", key} when key in @string_intrinsics ->
        if intrinsic_string_operator?(key, op),
          do: {:ok, {"intrinsic.string", key, op, value}},
          else: {:error, :unsupported_trace_selector}

      {:ok, scope, key} when scope != "intrinsic" ->
        {:ok, {scope <> ".string", key, op, value}}

      _ ->
        {:error, :unsupported_trace_selector}
    end
  end

  defp predicate(field, op, {:word, value})
       when field in ["status", "span:status"] and value in ~w(unset ok error) and op in ["=", "!="] do
    {:ok, {"intrinsic", "status", op, Integer.to_string(Enum.find_index(~w(unset ok error), &(&1 == value)))}}
  end

  defp predicate(field, op, {:word, value})
       when field in ["kind", "span:kind"] and value in ~w(unspecified internal server client producer consumer) and
              op in ["=", "!="] do
    {:ok,
     {"intrinsic", "kind", op,
      Integer.to_string(Enum.find_index(~w(unspecified internal server client producer consumer), &(&1 == value)))}}
  end

  defp predicate(field, op, {:word, value})
       when field in ["duration", "span:duration", "traceDuration", "trace:duration", "event:timeSinceStart"] and
              op in @comparisons do
    key = Map.get(@aliases, field, field)
    with {:ok, ns} <- duration(value), do: {:ok, {"intrinsic", key, op, Integer.to_string(ns)}}
  end

  defp predicate(field, op, {:word, value}) when op in @comparisons do
    cond do
      value in ["true", "false"] and op in ["=", "!="] ->
        typed_predicate(field, "bool", op, value)

      Regex.match?(@float, value) ->
        normalized = value |> String.replace(~r/\A(-?)\./, "\\g{1}0.") |> String.replace(~r/\.(?=[eE]|\z)/, ".0")

        with {number, ""} <- Float.parse(normalized),
             do: typed_predicate(field, "float", op, Float.to_string(number))

      true ->
        numeric_predicate(field, op, value)
    end
  end

  defp predicate(_, _, _), do: {:error, :unsupported_trace_selector}

  defp typed_predicate(field, type, op, value) do
    case field(field) do
      {:ok, scope, key} when scope != "intrinsic" -> {:ok, {scope <> "." <> type, key, op, value}}
      _ -> {:error, :unsupported_trace_selector}
    end
  end

  defp numeric_predicate(field, op, value) do
    with {:ok, scope, key} when scope != "intrinsic" <- field(field),
         {number, ""} when number >= -@max_int - 1 and number <= @max_int <- Integer.parse(value) do
      {:ok, {scope <> ".int", key, op, Integer.to_string(number)}}
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

  @doc "Whether the program requires capability-8 empty/typed/intrinsic search support."
  def typed?(program) do
    Enum.any?(program, fn {scope, key, op, _} ->
      scope in ["constant", "intrinsic.string"] or
        (scope == "intrinsic" and key == "kind") or
        (scope == "select" and key == "intrinsic" and op == "name") or
        String.ends_with?(scope, [".bool", ".float", ".any"])
    end)
  end

  @doc "Whether matching requires complete retained trace bounds (search capability 9)."
  def trace_duration?(program), do: Enum.any?(program, &match?({"intrinsic", "trace_duration", _, _}, &1))

  @doc "Whether search requires complete retained trace context, not a time horizon."
  def context?(program),
    do:
      trace_duration?(program) or
        Enum.any?(program, fn
          {"intrinsic.string", key, _, _} -> key in ~w(rootName rootServiceName)
          {"select", "intrinsic", key, _} -> key in ~w(rootName rootServiceName trace_duration)
          _ -> false
        end)

  @doc "Whether the program needs capability-10 scoped/intrinsic evaluation."
  def scoped?(program),
    do:
      Enum.any?(program, fn
        {"intrinsic.string", key, _, _} -> key != "name"
        {"intrinsic", "event:timeSinceStart", _, _} -> true
        {"select", "intrinsic", key, _} -> key not in ~w(name status kind)
        {"select", scope, _, _} -> scope in ~w(link instrumentation)
        {scope, _, _, _} -> String.starts_with?(scope, ["link.", "instrumentation."])
      end)

  defp valid_select?({"select", scope, key, ""}) when scope in @owners, do: byte_size(key) in 1..256

  defp valid_select?({"select", "intrinsic", key, ""}), do: key in @intrinsics
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

  defp valid_leaf?({"constant", "", "true", ""}), do: true

  defp valid_leaf?({scope, key, op, value}) when scope in @string_scopes do
    valid_string_field?(scope, key, op) and
      byte_size(key) in 1..256 and byte_size(value) <= 4096 and
      valid_string_comparison?(op, value)
  end

  defp valid_leaf?({scope, key, op, value}) when scope in @int_scopes do
    byte_size(key) in 1..256 and byte_size(value) <= 20 and op in @comparisons and valid_integer?(scope, key, op, value)
  end

  defp valid_leaf?({scope, key, op, value}) when scope in @float_scopes do
    byte_size(key) in 1..256 and byte_size(value) <= 128 and op in @comparisons and
      match?({_, ""}, Float.parse(value))
  end

  defp valid_leaf?({scope, key, op, value}) when scope in @bool_scopes do
    byte_size(key) in 1..256 and op in ["=", "!="] and value in ["true", "false"]
  end

  defp valid_leaf?({scope, key, op, "nil"}) when scope in @any_scopes,
    do: byte_size(key) in 1..256 and op in ["=", "!="]

  defp valid_leaf?(_), do: false

  defp valid_string_field?("intrinsic.string", key, op),
    do: key in @string_intrinsics and intrinsic_string_operator?(key, op)

  defp valid_string_field?(_scope, _key, _op), do: true

  defp intrinsic_string_operator?(key, op),
    do: key not in ~w(span:id span:parentID trace:id link:spanID link:traceID) or op in ["=", "!="]

  defp valid_string_comparison?(op, _value) when op in ["=", "!="], do: true

  defp valid_string_comparison?(op, value) when op in ["=~", "!~"] do
    byte_size(value) <= 1024 and NIF.validate_metric_regex(value) == :ok and
      NIF.validate_metric_regex(Pulse.QueryRegex.anchor(value)) == :ok
  end

  defp valid_string_comparison?(_op, _value), do: false

  defp valid_integer?(scope, key, op, value) do
    case Integer.parse(value) do
      {number, ""} when number >= -@max_int - 1 and number <= @max_int ->
        valid_integer_domain?(scope, key, op, number)

      _ ->
        false
    end
  end

  defp valid_integer_domain?("intrinsic", "status", op, number), do: number in 0..2 and op in ["=", "!="]
  defp valid_integer_domain?("intrinsic", "kind", op, number), do: number in 0..5 and op in ["=", "!="]

  defp valid_integer_domain?("intrinsic", key, _op, number)
       when key in ["duration", "trace_duration", "event:timeSinceStart"], do: number >= 0

  defp valid_integer_domain?("intrinsic", _key, _op, _number), do: false
  defp valid_integer_domain?(_scope, _key, _op, _number), do: true
end
