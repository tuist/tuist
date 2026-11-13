defmodule Pulse.PromQL.Formatter do
  @moduledoc "Single-line formatting of Pulse's supported PromQL grammar."

  alias Pulse.PromQL.Parser

  @operators %{eq: "=", neq: "!=", re: "=~", nre: "!~"}
  @precedence %{
    "or" => 1,
    "and" => 2,
    "unless" => 2,
    "==" => 3,
    "!=" => 3,
    ">" => 3,
    "<" => 3,
    ">=" => 3,
    "<=" => 3,
    "</" => 3,
    ">/" => 3,
    "+" => 4,
    "-" => 4,
    "*" => 5,
    "/" => 5,
    "%" => 5,
    "atan2" => 5,
    "^" => 7
  }

  @spec format(String.t()) :: {:ok, String.t()} | {:error, term()}
  def format(text) do
    with {:ok, expression} <- Parser.parse(text) do
      formatted = expression |> render() |> IO.iodata_to_binary()

      # Escapes and fixed-decimal literals can expand. Never return a query
      # that the same parser would reject for exceeding its input budget.
      if byte_size(formatted) <= Pulse.QueryLimits.max_promql_query_bytes(),
        do: {:ok, formatted},
        else: {:error, :query_expression_limit}
    end
  end

  defp render({:selector, matchers, shift}), do: [selector(matchers), offset(shift)]

  defp render({:range, matchers, window, shift}), do: [selector(matchers), "[", duration(window), "]", offset(shift)]

  defp render({:subquery, inner, window, step, shift}),
    do: [operand(inner, 8, false), "[", duration(window), ":", duration(step), "]", offset(shift)]

  defp render({:function, name, range}), do: [Atom.to_string(name), "(", render(range), ")"]
  defp render({:call, name, args}), do: [name, "(", Enum.map_intersperse(args, ", ", &render/1), ")"]
  defp render({:aggregate, name, group, inner}), do: [Atom.to_string(name), grouping(group), "(", render(inner), ")"]

  defp render({:parameter_aggregate, name, group, parameter, inner}),
    do: [name, grouping(group), "(", render(parameter), ", ", render(inner), ")"]

  defp render({:binary, op, modifiers, left, right}) do
    rank = Map.fetch!(@precedence, op)

    [
      operand(left, rank, op == "^"),
      " ",
      op,
      Enum.map(modifiers, &modifier/1),
      " ",
      operand(right, rank, op != "^")
    ]
  end

  defp render({:unary, op, inner}), do: [op, operand(inner, 8, false)]
  defp render({:string, text}), do: Pulse.JSON.encode!(text)
  defp render({:scalar, :nan}), do: "NaN"
  defp render({:scalar, :infinity}), do: "Inf"
  defp render({:scalar, value}), do: number(value)
  defp render({:duration_number, text}), do: text
  defp render({:duration_literal, 0}), do: "0s"
  defp render({:duration_literal, ns}), do: [if(ns < 0, do: "-", else: ""), duration(abs(ns))]

  # Equal precedence still needs parentheses on the non-associative side.
  # In particular, a - (b - c) and (a ^ b) ^ c must retain their trees.
  defp operand(expression, parent, equal?) do
    rank = precedence(expression)
    text = render(expression)
    if rank < parent or (rank == parent and equal?), do: ["(", text, ")"], else: text
  end

  defp precedence({:binary, op, _, _, _}), do: Map.fetch!(@precedence, op)
  defp precedence({:unary, _, _}), do: 6
  defp precedence(_), do: 8

  defp grouping(nil), do: []

  defp grouping({:grouping, mode, labels}),
    do: [" ", Atom.to_string(mode), " (", Enum.map_intersperse(labels, ", ", &label/1), ") "]

  defp modifier("bool"), do: " bool"
  defp modifier([mode]), do: [" ", mode]
  defp modifier([mode, labels]), do: [" ", mode, " (", Enum.map_intersperse(labels, ", ", &label/1), ")"]

  defp selector([{"__name__", :eq, name} | rest] = matchers) do
    # Bare NaN/Inf are scalars, even when a stored metric has that name.
    if Regex.match?(~r/\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/, name) and String.downcase(name) not in ["nan", "inf"],
      do: [name, matchers(rest)],
      else: matchers(matchers)
  end

  defp selector(matchers), do: matchers(matchers)
  defp matchers([]), do: []

  defp matchers(matchers) do
    ["{", Enum.map_intersperse(matchers, ",", &matcher/1), "}"]
  end

  defp matcher({name, op, value}) do
    [label(name), Map.fetch!(@operators, op), Pulse.JSON.encode!(value)]
  end

  defp label(name), do: if(Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, name), do: name, else: Pulse.JSON.encode!(name))

  defp offset(0), do: []

  defp offset({:at, anchor, shift}),
    do: [" @ ", if(is_binary(anchor), do: [anchor, "()"], else: seconds(anchor)), offset(shift)]

  defp offset(value) when value < 0, do: [" offset -", duration(-value)]
  defp offset(value), do: [" offset ", duration(value)]

  defp duration(nil), do: []
  defp duration({:duration, expr}), do: ["(", render(expr), ")"]
  defp duration(value) when rem(value, 1_000_000) != 0, do: seconds(value)

  defp duration(value) do
    # Whole years/weeks are compact; mixed values stay in days and smaller units.
    units = [
      {"y", 31_536_000_000_000_000},
      {"w", 604_800_000_000_000},
      {"d", 86_400_000_000_000},
      {"h", 3_600_000_000_000},
      {"m", 60_000_000_000},
      {"s", 1_000_000_000},
      {"ms", 1_000_000}
    ]

    {parts, 0} =
      Enum.map_reduce(units, value, fn {unit, size}, remaining ->
        count = div(remaining, size)

        if count > 0 and (unit not in ["y", "w"] or rem(remaining, size) == 0),
          do: {[Integer.to_string(count), unit], rem(remaining, size)},
          else: {[], remaining}
      end)

    parts
  end

  defp seconds(value) do
    whole = div(abs(value), 1_000_000_000)
    fraction = rem(abs(value), 1_000_000_000)
    sign = if value < 0, do: "-", else: ""

    if fraction == 0 do
      [sign, Integer.to_string(whole)]
    else
      digits = fraction |> Integer.to_string() |> String.pad_leading(9, "0") |> String.trim_trailing("0")
      [sign, Integer.to_string(whole), ".", digits]
    end
  end

  # Fixed decimal avoids lexical changes such as leading-zero octal integers
  # and preserves the shortest round-tripping float, including subnormals.
  defp number(value) do
    case String.split(Float.to_string(value), "e") do
      [plain] ->
        String.trim_trailing(plain, ".0")

      [mantissa, exponent] ->
        [whole, fraction] = String.split(mantissa, ".")
        digits = String.trim_trailing(whole <> fraction, "0")
        position = byte_size(whole) + String.to_integer(exponent)

        cond do
          position <= 0 ->
            ["0.", String.duplicate("0", -position), digits]

          position >= byte_size(digits) ->
            [digits, String.duplicate("0", position - byte_size(digits))]

          true ->
            <<whole::binary-size(^position), fraction::binary>> = digits
            [whole, ".", fraction]
        end
    end
  end
end
