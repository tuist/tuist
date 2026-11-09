defmodule Pulse.PromQL.Parser do
  @moduledoc """
  Parser for Pulse's initial Prometheus Query Language subset.

  Supports named and label-only selectors, range functions, nested vector
  aggregations with by/without grouping, parentheses, signed offsets and fixed
  evaluation times.
  Unsupported syntax fails rather than being interpreted as another language.
  """
  import NimbleParsec

  alias Pulse.Codec.NIF
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Time

  @max_query_bytes Pulse.QueryLimits.max_promql_query_bytes()

  comment = string("#") |> repeat(utf8_char(not: ?\n))
  ws = ignore(repeat(choice([ascii_char([?\s, ?\t, ?\r, ?\n]), comment])))
  defcombinatorp(:ws, ws)

  keyword = fn text ->
    text
    |> String.to_charlist()
    |> Enum.reduce(empty(), fn char, acc ->
      next = if char in ?a..?z, do: ascii_char([char, char - 32]), else: string(<<char>>)
      concat(acc, next)
    end)
    |> replace(text)
  end

  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_, ?:])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> reduce({List, :to_string, []})

  defcombinatorp(:identifier, identifier)

  escape =
    ignore(string("\\"))
    |> choice([
      string("n") |> replace(?\n),
      string("r") |> replace(?\r),
      string("t") |> replace(?\t),
      string("a") |> replace(7),
      string("b") |> replace(8),
      string("f") |> replace(12),
      string("v") |> replace(11),
      string("\\") |> replace(?\\),
      string("\"") |> replace(?"),
      string("'") |> replace(?'),
      ignore(string("x")) |> ascii_string([?0..?9, ?a..?f, ?A..?F], 2) |> reduce({__MODULE__, :hex_byte, []}),
      ignore(string("u")) |> ascii_string([?0..?9, ?a..?f, ?A..?F], 4) |> reduce({__MODULE__, :hex, []}),
      ignore(string("U")) |> ascii_string([?0..?9, ?a..?f, ?A..?F], 8) |> reduce({__MODULE__, :hex, []}),
      ascii_string([?0..?7], 3) |> reduce({__MODULE__, :octal, []})
    ])

  quoted =
    choice([
      ignore(string("\"")) |> repeat(choice([escape, utf8_char(not: ?", not: ?\\, not: ?\n)])) |> ignore(string("\"")),
      ignore(string("'")) |> repeat(choice([escape, utf8_char(not: ?', not: ?\\, not: ?\n)])) |> ignore(string("'")),
      ignore(string("`")) |> repeat(utf8_char(not: ?`)) |> ignore(string("`"))
    ])
    |> reduce({__MODULE__, :decode_string, []})

  label_identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})

  matcher =
    choice([label_identifier, quoted])
    |> parsec(:ws)
    |> choice([
      string("=~") |> replace(:re),
      string("!~") |> replace(:nre),
      string("!=") |> replace(:neq),
      string("=") |> replace(:eq)
    ])
    |> parsec(:ws)
    |> concat(quoted)
    |> reduce({__MODULE__, :matcher, []})

  matcher = parsec(:ws) |> choice([matcher, quoted |> reduce({__MODULE__, :metric_name, []})])

  labels =
    ignore(string("{"))
    |> parsec(:ws)
    |> optional(
      matcher
      |> repeat(parsec(:ws) |> ignore(string(",")) |> concat(matcher))
      |> optional(parsec(:ws) |> ignore(string(",")))
    )
    |> parsec(:ws)
    |> ignore(string("}"))
    |> wrap()

  selector =
    choice([
      identifier |> optional(parsec(:ws) |> concat(labels)),
      labels
    ])
    |> reduce({__MODULE__, :selector, []})

  defcombinatorp(:selector, selector)

  component =
    ascii_string([?0..?9], min: 1)
    |> choice(Enum.map(["ms", "s", "m", "h", "d", "w", "y"], &string/1))
    |> reduce({__MODULE__, :duration_component, []})

  seconds =
    choice([
      ascii_string([?0..?9], min: 1) |> optional(string(".") |> optional(ascii_string([?0..?9], min: 1))),
      string(".") |> ascii_string([?0..?9], min: 1)
    ])
    |> optional(
      choice([string("e"), string("E")])
      |> optional(choice([string("+"), string("-")]))
      |> ascii_string([?0..?9], min: 1)
    )
    |> reduce({IO, :iodata_to_binary, []})

  digits = ascii_string([?0..?9], 1) |> optional(ascii_string([?0..?9, ?_], min: 1))
  hex_digits = ascii_string([?0..?9, ?a..?f, ?A..?F, ?_], min: 1)
  exponent = optional(choice([string("+"), string("-")])) |> concat(digits)

  decimal_number =
    choice([
      digits |> optional(string(".") |> optional(digits)),
      string(".") |> concat(digits)
    ])
    |> optional(choice([string("e"), string("E")]) |> concat(exponent))

  hex_number = choice([string("0x"), string("0X")]) |> concat(hex_digits)
  numeric_text = choice([hex_number, decimal_number]) |> reduce({IO, :iodata_to_binary, []})
  number = numeric_text |> reduce({__MODULE__, :number, []})

  unit_duration = times(component, min: 1) |> reduce({__MODULE__, :duration, []})
  # HTTP duration parameters retain their literal decimal/unit grammar.
  duration = choice([unit_duration, seconds |> reduce({__MODULE__, :seconds_duration, []})])
  defcombinatorp(:duration, duration)

  duration_call =
    choice([
      choice([keyword.("step"), keyword.("range")])
      |> parsec(:ws)
      |> ignore(string("("))
      |> parsec(:ws)
      |> ignore(string(")")),
      choice([keyword.("min_of"), keyword.("max_of")])
      |> parsec(:ws)
      |> ignore(string("("))
      |> parsec(:duration_expression)
      |> ignore(string(","))
      |> parsec(:duration_expression)
      |> ignore(string(")"))
    ])
    |> reduce({__MODULE__, :call, []})

  defcombinatorp(
    :duration_atom,
    parsec(:ws)
    |> choice([
      duration_call,
      ignore(string("(")) |> parsec(:duration_expression) |> ignore(string(")")),
      unit_duration |> reduce({__MODULE__, :duration_literal, []}),
      numeric_text |> reduce({__MODULE__, :duration_number, []})
    ])
    |> parsec(:ws)
  )

  # An unparenthesized offset ends before any arithmetic operator, including
  # power: `x offset -2 ^ 2` is `(x offset -2) ^ 2`.
  defcombinatorp(
    :duration_signed_atom,
    optional(choice([string("+"), string("-")]) |> parsec(:ws))
    |> parsec(:duration_atom)
    |> reduce({__MODULE__, :duration_unary, []})
  )

  defcombinatorp(
    :duration_power,
    parsec(:duration_atom)
    |> optional(string("^") |> parsec(:duration_unary_expression))
    |> reduce({__MODULE__, :duration_power, []})
  )

  defcombinatorp(
    :duration_unary_expression,
    parsec(:ws)
    |> choice([
      choice([string("+"), string("-")])
      |> parsec(:ws)
      |> parsec(:duration_unary_expression)
      |> reduce({__MODULE__, :duration_unary, []}),
      parsec(:duration_power)
    ])
  )

  for {name, operand, operators} <- [
        {:duration_product, :duration_unary_expression, ["*", "/", "%"]},
        {:duration_expression, :duration_product, ["+", "-"]}
      ] do
    defcombinatorp(
      name,
      parsec(operand)
      |> repeat(choice(Enum.map(operators, &string/1)) |> parsec(operand) |> wrap())
      |> reduce({__MODULE__, :duration_binary, []})
    )
  end

  duration_expression = parsec(:duration_expression) |> reduce({__MODULE__, :duration_expression, []})

  offset =
    parsec(:ws)
    |> ignore(keyword.("offset"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> parsec(:ws)
    |> parsec(:duration_signed_atom)
    |> reduce({__MODULE__, :duration_expression, []})
    |> unwrap_and_tag(:offset)

  anchor =
    parsec(:ws)
    |> ignore(string("@"))
    |> parsec(:ws)
    |> choice([
      choice([keyword.("start"), keyword.("end")])
      |> parsec(:ws)
      |> ignore(string("("))
      |> parsec(:ws)
      |> ignore(string(")")),
      optional(choice([string("+"), string("-")]) |> parsec(:ws))
      |> choice([unit_duration, numeric_text])
      |> reduce({__MODULE__, :anchor_timestamp, []})
    ])
    |> unwrap_and_tag(:at)

  temporal = repeat(choice([offset, anchor])) |> reduce({__MODULE__, :temporal, []})
  instant = selector |> concat(temporal) |> reduce({__MODULE__, :instant, []})

  range =
    selector
    |> parsec(:ws)
    |> ignore(string("["))
    |> concat(duration_expression)
    |> ignore(string("]"))
    |> concat(temporal)
    |> reduce({__MODULE__, :range, []})

  functions =
    ~w(rate increase irate idelta delta changes resets deriv sum_over_time avg_over_time min_over_time max_over_time count_over_time stddev_over_time stdvar_over_time mad_over_time absent_over_time present_over_time first_over_time last_over_time ts_of_first_over_time ts_of_last_over_time ts_of_min_over_time ts_of_max_over_time)

  function =
    choice(Enum.map(functions, &(string(&1) |> replace(String.to_existing_atom(&1)))))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> parsec(:ws)
    |> ignore(string("("))
    |> parsec(:ws)
    |> concat(range)
    |> parsec(:ws)
    |> ignore(string(")"))
    |> reduce({__MODULE__, :function, []})

  grouping =
    choice([keyword.("by") |> replace(:by), keyword.("without") |> replace(:without)])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> parsec(:ws)
    |> ignore(string("("))
    |> parsec(:ws)
    |> optional(
      choice([label_identifier, quoted])
      |> repeat(parsec(:ws) |> ignore(string(",")) |> parsec(:ws) |> choice([label_identifier, quoted]))
      |> optional(parsec(:ws) |> ignore(string(",")))
    )
    |> parsec(:ws)
    |> ignore(string(")"))
    |> reduce({__MODULE__, :grouping, []})

  aggregate =
    choice(
      Enum.map(~w(sum avg min max count group stddev stdvar), fn op ->
        op
        |> String.to_charlist()
        |> Enum.reduce(empty(), fn char, acc -> concat(acc, ascii_char([char, char - 32])) end)
        |> replace(String.to_existing_atom(op))
      end)
    )
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> parsec(:ws)
    |> optional(grouping |> parsec(:ws))
    |> ignore(string("("))
    |> parsec(:expression)
    |> parsec(:ws)
    |> ignore(string(")"))
    |> optional(parsec(:ws) |> concat(grouping))
    |> reduce({__MODULE__, :aggregate, []})

  aggregation_prefix =
    choice(
      Enum.map(
        ~w(sum avg min max count group stddev stdvar topk bottomk quantile count_values limitk limit_ratio),
        fn op ->
          keyword.(op) |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
        end
      )
    )

  generic_function =
    lookahead_not(aggregation_prefix)
    |> concat(identifier)
    |> parsec(:ws)
    |> ignore(string("("))
    |> parsec(:ws)
    |> optional(parsec(:argument) |> repeat(parsec(:ws) |> ignore(string(",")) |> parsec(:argument)))
    |> parsec(:ws)
    |> ignore(string(")"))
    |> reduce({__MODULE__, :call, []})

  parameter_aggregate =
    choice(Enum.map(~w(topk bottomk quantile count_values limitk limit_ratio), keyword))
    |> parsec(:ws)
    |> optional(grouping |> parsec(:ws))
    |> ignore(string("("))
    |> parsec(:expression)
    |> ignore(string(","))
    |> parsec(:expression)
    |> ignore(string(")"))
    |> optional(parsec(:ws) |> concat(grouping))
    |> reduce({__MODULE__, :parameter_aggregate, []})

  special_number =
    choice([keyword.("nan") |> replace(:nan), keyword.("inf") |> replace(:infinity)])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> reduce({__MODULE__, :special_number, []})

  subquery_suffix =
    ignore(string("["))
    |> concat(duration_expression)
    |> ignore(string(":"))
    |> choice([duration_expression, empty() |> replace(nil)])
    |> parsec(:ws)
    |> ignore(string("]"))
    |> concat(temporal)
    |> wrap()

  primary =
    parsec(:ws)
    |> choice([
      parameter_aggregate,
      aggregate,
      function,
      generic_function,
      special_number,
      quoted |> reduce({__MODULE__, :string_argument, []}),
      ignore(string("(")) |> parsec(:expression) |> ignore(string(")")),
      unit_duration |> reduce({__MODULE__, :duration_scalar, []}),
      number,
      range,
      instant
    ])
    |> parsec(:ws)
    |> optional(subquery_suffix)
    |> reduce({__MODULE__, :subquery, []})
    |> parsec(:ws)

  defcombinatorp(:primary, primary)

  defcombinatorp(
    :range_argument,
    choice([
      range,
      ignore(string("("))
      |> parsec(:ws)
      |> parsec(:range_argument)
      |> parsec(:ws)
      |> ignore(string(")"))
    ])
  )

  defcombinatorp(
    :argument,
    parsec(:ws)
    |> choice([parsec(:range_argument), quoted |> reduce({__MODULE__, :string_argument, []}), parsec(:expression)])
    |> parsec(:ws)
  )

  # Power is right-associative; unary signs bind less tightly than power.
  defcombinatorp(
    :power,
    parsec(:primary)
    |> optional(string("^") |> parsec(:modifiers) |> parsec(:unary))
    |> reduce({__MODULE__, :power, []})
  )

  defcombinatorp(
    :unary,
    parsec(:ws)
    |> choice([
      choice([string("+"), string("-")]) |> parsec(:ws) |> parsec(:unary) |> reduce({__MODULE__, :unary, []}),
      parsec(:power)
    ])
  )

  label_list =
    ignore(string("("))
    |> parsec(:ws)
    |> optional(
      choice([label_identifier, quoted])
      |> repeat(parsec(:ws) |> ignore(string(",")) |> parsec(:ws) |> choice([label_identifier, quoted]))
      |> optional(parsec(:ws) |> ignore(string(",")))
    )
    |> parsec(:ws)
    |> ignore(string(")"))
    |> wrap()

  matching =
    choice([keyword.("on"), keyword.("ignoring")])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> parsec(:ws)
    |> concat(label_list)
    |> wrap()

  cardinality =
    choice([keyword.("group_left"), keyword.("group_right")])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:]))
    |> parsec(:ws)
    |> optional(label_list)
    |> wrap()

  modifiers =
    parsec(:ws)
    |> optional(keyword.("bool") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:])) |> parsec(:ws))
    |> optional(matching |> parsec(:ws))
    |> optional(cardinality |> parsec(:ws))
    |> wrap()

  defcombinatorp(:modifiers, modifiers)

  for {name, operand, operators} <- [
        {:product, :unary, ["*", "/", "%", "atan2"]},
        {:addition, :product, ["+", "-"]},
        {:comparison, :addition, ["==", "!=", ">=", "<=", ">/", "</", ">", "<"]},
        {:intersection, :comparison, ["and", "unless"]},
        {:expression, :intersection, ["or"]}
      ] do
    choices =
      Enum.map(operators, fn op ->
        token = keyword.(op)

        if op in ["atan2", "and", "unless", "or"],
          do: token |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:])),
          else: token
      end)

    operator =
      case choices do
        [only] -> only
        many -> choice(many)
      end

    defcombinatorp(
      name,
      parsec(operand)
      |> repeat(operator |> concat(modifiers) |> parsec(operand) |> wrap())
      |> reduce({__MODULE__, :binary, []})
    )
  end

  defparsecp(:do_parse, parsec(:expression) |> eos())
  defparsecp(:do_parse_duration, duration |> eos())

  # These atoms are an explicit, closed operation set, never derived from input.
  @operations [
    :rate,
    :increase,
    :irate,
    :idelta,
    :delta,
    :changes,
    :resets,
    :deriv,
    :sum_over_time,
    :avg_over_time,
    :min_over_time,
    :max_over_time,
    :count_over_time,
    :stddev_over_time,
    :stdvar_over_time,
    :mad_over_time,
    :absent_over_time,
    :present_over_time,
    :first_over_time,
    :last_over_time,
    :ts_of_first_over_time,
    :ts_of_last_over_time,
    :ts_of_min_over_time,
    :ts_of_max_over_time,
    :sum,
    :avg,
    :min,
    :max,
    :count,
    :group,
    :stddev,
    :stdvar
  ]
  @factors %{
    "ms" => 1_000_000,
    "s" => 1_000_000_000,
    "m" => 60_000_000_000,
    "h" => 3_600_000_000_000,
    "d" => 86_400_000_000_000,
    "w" => 604_800_000_000_000,
    "y" => 31_536_000_000_000_000
  }

  # Grafana expands All selections into literal alternations, commonly tens
  # of KiB on fleet dashboards. Text size is independent of AST complexity.
  def parse(input) when is_binary(input) and byte_size(input) <= @max_query_bytes do
    case do_parse(input) do
      {:ok, [expr], "", _, _, _} ->
        if bounded?(expr), do: validate(expr), else: {:error, :query_expression_limit}

      _ ->
        {:error, :invalid_or_unsupported_query}
    end
  rescue
    ArgumentError -> {:error, :invalid_or_unsupported_query}
  end

  def parse(_), do: {:error, :invalid_or_unsupported_query}

  def parse_duration(input) when is_binary(input) and byte_size(input) <= 128 do
    case do_parse_duration(input) do
      {:ok, [duration], "", _, _, _} when duration > 0 -> {:ok, duration}
      _ -> {:error, :invalid_duration}
    end
  rescue
    ArgumentError -> {:error, :invalid_duration}
  end

  def parse_duration(_), do: {:error, :invalid_duration}

  @doc false
  def hex([s]), do: String.to_integer(s, 16)
  @doc false
  def octal([s]), do: escaped_byte(String.to_integer(s, 8))
  @doc false
  def hex_byte([s]), do: escaped_byte(String.to_integer(s, 16))
  defp escaped_byte(byte) when byte <= 255, do: <<byte>>
  defp escaped_byte(_), do: raise(ArgumentError)
  @doc false
  def decode_string(parts) do
    result =
      parts
      |> Enum.map(fn
        char when is_integer(char) -> <<char::utf8>>
        bytes -> bytes
      end)
      |> IO.iodata_to_binary()

    if String.valid?(result), do: result, else: raise(ArgumentError)
  end

  @doc false
  def matcher([name, op, value]), do: {name, op, value}
  @doc false
  def metric_name([""]), do: raise(ArgumentError)
  def metric_name([name]), do: {:metric_name, name}
  @doc false
  def selector([name, matchers]), do: selector_matchers([{:metric_name, name} | matchers])
  def selector([name]) when is_binary(name), do: selector_matchers([{:metric_name, name}])
  def selector([matchers]), do: selector_matchers(matchers)

  defp selector_matchers(matchers) do
    # Keep shorthand names distinct until assembly, so two bare metric names
    # cannot silently turn into contradictory __name__ matchers.
    if Enum.count(matchers, &match?({:metric_name, _}, &1)) > 1, do: raise(ArgumentError)

    Enum.map(matchers, fn
      {:metric_name, name} -> {"__name__", :eq, name}
      matcher -> matcher
    end)
  end

  @doc false
  def duration_component([n, unit]), do: {String.to_integer(n), unit}
  @doc false
  def duration(parts) do
    units = Enum.map(parts, fn {_, unit} -> Map.fetch!(@factors, unit) end)
    if units != Enum.sort(Enum.uniq(units), :desc), do: raise(ArgumentError)
    total = Enum.reduce(parts, 0, fn {n, unit}, sum -> sum + n * Map.fetch!(@factors, unit) end)
    if total > 31_536_000_000_000_000, do: raise(ArgumentError)
    total
  end

  @doc false
  def seconds_duration([text]) do
    case literal_time(text) do
      {:ok, ns} when ns <= 31_536_000_000_000_000 -> ns
      _ -> raise(ArgumentError)
    end
  end

  @doc false
  def signed_duration(["-", value]), do: -value
  def signed_duration(["+", value]), do: value
  def signed_duration([value]), do: value

  @doc false
  def duration_scalar([ns]), do: {:scalar, Time.seconds(ns)}
  @doc false
  def duration_literal([ns]), do: {:duration_literal, ns}
  @doc false
  def duration_number([text]) do
    seconds_duration([text])
    {:duration_number, text}
  end

  @doc false
  def duration_expression([{:duration_literal, ns}]), do: ns
  def duration_expression([{:duration_number, text}]), do: seconds_duration([text])
  def duration_expression([{:unary, "-", {:duration_number, text}}]), do: -seconds_duration([text])
  def duration_expression([expr]), do: {:duration, expr}
  @doc false
  def duration_unary([expr]), do: expr
  def duration_unary(["+", expr]), do: expr
  def duration_unary(["-", {:duration_literal, ns}]), do: {:duration_literal, -ns}
  def duration_unary([op, expr]), do: {:unary, op, expr}
  @doc false
  def duration_power([expr]), do: expr
  def duration_power([left, "^", right]), do: {:binary, "^", [], left, right}
  @doc false
  def duration_binary([left | rest]),
    do: Enum.reduce(rest, left, fn [op, right], left -> {:binary, op, [], left, right} end)

  @doc false
  def anchor_timestamp(parts) do
    case List.last(parts) do
      ns when is_integer(ns) ->
        signed_duration(parts)

      _ ->
        case literal_time(IO.iodata_to_binary(parts)) do
          {:ok, ns} -> ns
          _ -> raise(ArgumentError)
        end
    end
  end

  # Keep PromQL's leading-zero octal integers, but parse decimal seconds
  # exactly instead of rounding contemporary timestamps through a float.
  defp literal_time(text) when byte_size(text) <= 128 do
    if not match?({:ok, _}, FloatParser.parse(text, :literal)), do: raise(ArgumentError)
    plain = String.replace(text, "_", "")

    case Regex.run(~r/\A([+-]?)(?:0[xX]([0-9a-fA-F]+)|(0[0-7]+))\z/, plain) do
      [_, sign, hex] ->
        value = String.to_integer(hex, 16)
        Time.parse_seconds(if(sign == "-", do: -value, else: value))

      [_, sign, "", octal] ->
        value = String.to_integer(octal, 8)
        Time.parse_seconds(if(sign == "-", do: -value, else: value))

      _ ->
        Time.parse_seconds(plain)
    end
  end

  defp literal_time(_), do: {:error, :invalid_timestamp}

  @doc false
  def temporal(parts) do
    if length(parts) != length(Enum.uniq_by(parts, &elem(&1, 0))), do: raise(ArgumentError)
    shift = Keyword.get(parts, :offset, 0)
    if Keyword.has_key?(parts, :at), do: {:at, Keyword.fetch!(parts, :at), shift}, else: shift
  end

  @doc false
  def instant([matchers]), do: {:selector, matchers, 0}
  def instant([matchers, offset]), do: {:selector, matchers, offset}
  @doc false
  def range([matchers, window]), do: {:range, matchers, window, 0}
  def range([matchers, window, offset]), do: {:range, matchers, window, offset}
  @doc false
  def function([op, range]) when op in @operations, do: {:function, op, range}
  @doc false
  def grouping([mode | labels]), do: {:grouping, mode, labels}
  @doc false
  def aggregate([op, {:grouping, _, _} = group, inner]), do: {:aggregate, op, group, inner}
  def aggregate([op, inner, {:grouping, _, _} = group]), do: {:aggregate, op, group, inner}
  def aggregate([op, inner]), do: {:aggregate, op, nil, inner}
  def aggregate(_), do: raise(ArgumentError)

  @doc false
  def number(parts) do
    text = IO.iodata_to_binary(parts)

    case FloatParser.parse(text, :literal) do
      {:ok, value} -> {:scalar, value}
      :error -> raise ArgumentError
    end
  end

  @doc false
  def special_number([value]), do: {:scalar, value}
  @doc false
  def string_argument([text]), do: {:string, text}
  @doc false
  def call([name | args]), do: {:call, name, args}
  @doc false
  def subquery([inner]), do: inner
  def subquery([inner, [window, step]]), do: {:subquery, inner, window, step, 0}
  def subquery([inner, [window, step, offset]]), do: {:subquery, inner, window, step, offset}
  @doc false
  def parameter_aggregate([op, {:grouping, _, _} = group, parameter, inner]),
    do: {:parameter_aggregate, op, group, parameter, inner}

  def parameter_aggregate([op, parameter, inner, {:grouping, _, _} = group]),
    do: {:parameter_aggregate, op, group, parameter, inner}

  def parameter_aggregate([op, parameter, inner]), do: {:parameter_aggregate, op, nil, parameter, inner}
  def parameter_aggregate(_), do: raise(ArgumentError)
  @doc false
  def power([inner]), do: inner
  def power([left, "^", modifiers, right]), do: {:binary, "^", modifiers, left, right}
  @doc false
  def unary([op, inner]), do: {:unary, op, inner}
  @doc false
  def binary([left | rest]),
    do: Enum.reduce(rest, left, fn [op, modifiers, right], left -> {:binary, op, modifiers, left, right} end)

  @doc false
  def type({:scalar, _}), do: :scalar
  def type({:string, _}), do: :string
  def type({:range, _, _, _}), do: :range
  def type({:subquery, _, _, _, _}), do: :range
  def type({:unary, _, inner}), do: type(inner)
  def type({:call, name, _}) when name in ~w(time scalar pi start end step range min_of max_of), do: :scalar

  def type({:binary, _, _, left, right}),
    do: if(type(left) == :scalar and type(right) == :scalar, do: :scalar, else: :vector)

  def type(_), do: :vector

  defp bounded?(expr), do: ast_size(expr, 0) <= 256
  defp ast_size(_expr, depth) when depth > 64, do: 257
  defp ast_size({:binary, _, _, left, right}, depth), do: 1 + ast_size(left, depth + 1) + ast_size(right, depth + 1)
  defp ast_size({:aggregate, _, _, inner}, depth), do: 1 + ast_size(inner, depth + 1)
  defp ast_size({:selector, _, offset}, depth), do: 1 + ast_size(offset, depth + 1)
  defp ast_size({:range, _, window, offset}, depth), do: 1 + ast_size(window, depth + 1) + ast_size(offset, depth + 1)

  defp ast_size({:subquery, inner, window, step, offset}, depth),
    do: 1 + Enum.sum(Enum.map([inner, window, step, offset], &ast_size(&1, depth + 1)))

  defp ast_size({:function, _, inner}, depth), do: 1 + ast_size(inner, depth + 1)
  defp ast_size({:at, _, offset}, depth), do: ast_size(offset, depth + 1)
  defp ast_size({:duration, inner}, depth), do: ast_size(inner, depth + 1)
  defp ast_size({:unary, _, inner}, depth), do: 1 + ast_size(inner, depth + 1)

  defp ast_size({:parameter_aggregate, _, _, parameter, inner}, depth),
    do: 1 + ast_size(parameter, depth + 1) + ast_size(inner, depth + 1)

  defp ast_size({:call, _, args}, depth), do: 1 + Enum.sum(Enum.map(args, &ast_size(&1, depth + 1)))
  defp ast_size(_, _), do: 1

  defp validate({type, _} = expr) when type in [:scalar, :string], do: {:ok, expr}

  defp validate({:unary, _, inner} = expr) do
    with {:ok, _} <- validate(inner),
         true <- type(inner) in [:scalar, :vector],
         do: {:ok, expr},
         else: (_ -> {:error, :invalid_operand})
  end

  defp validate({:call, name, args} = expr) do
    signatures = %{
      "histogram_quantile" => [:scalar, :vector],
      "histogram_fraction" => [:scalar, :scalar, :vector],
      "histogram_count" => [:vector],
      "histogram_sum" => [:vector],
      "histogram_avg" => [:vector],
      "histogram_stddev" => [:vector],
      "histogram_stdvar" => [:vector],
      "clamp" => [:vector, :scalar, :scalar],
      "clamp_min" => [:vector, :scalar],
      "clamp_max" => [:vector, :scalar],
      "vector" => [:scalar],
      "scalar" => [:vector],
      "time" => [],
      "pi" => [],
      "start" => [],
      "end" => [],
      "step" => [],
      "range" => [],
      "min_of" => [:scalar, :scalar],
      "max_of" => [:scalar, :scalar],
      "label_replace" => [:vector, :string, :string, :string, :string],
      "sort_desc" => [:vector],
      "sort" => [:vector],
      "year" => [:vector],
      "month" => [:vector],
      "day_of_month" => [:vector],
      "day_of_week" => [:vector],
      "day_of_year" => [:vector],
      "days_in_month" => [:vector],
      "hour" => [:vector],
      "minute" => [:vector],
      "round" => [:vector],
      "abs" => [:vector],
      "sgn" => [:vector],
      "floor" => [:vector],
      "ceil" => [:vector],
      "sqrt" => [:vector],
      "exp" => [:vector],
      "ln" => [:vector],
      "log2" => [:vector],
      "log10" => [:vector],
      "deg" => [:vector],
      "rad" => [:vector],
      "asin" => [:vector],
      "acos" => [:vector],
      "atan" => [:vector],
      "sin" => [:vector],
      "cos" => [:vector],
      "tan" => [:vector],
      "sinh" => [:vector],
      "cosh" => [:vector],
      "tanh" => [:vector],
      "asinh" => [:vector],
      "acosh" => [:vector],
      "atanh" => [:vector],
      "timestamp" => [:vector],
      "absent" => [:vector],
      "predict_linear" => [:range, :scalar],
      "quantile_over_time" => [:scalar, :range],
      "double_exponential_smoothing" => [:range, :scalar, :scalar],
      "holt_winters" => [:range, :scalar, :scalar],
      "rate" => [:range],
      "increase" => [:range],
      "irate" => [:range],
      "idelta" => [:range],
      "delta" => [:range],
      "changes" => [:range],
      "resets" => [:range],
      "deriv" => [:range],
      "sum_over_time" => [:range],
      "avg_over_time" => [:range],
      "min_over_time" => [:range],
      "max_over_time" => [:range],
      "count_over_time" => [:range],
      "stddev_over_time" => [:range],
      "stdvar_over_time" => [:range],
      "mad_over_time" => [:range],
      "absent_over_time" => [:range],
      "present_over_time" => [:range],
      "first_over_time" => [:range],
      "last_over_time" => [:range],
      "ts_of_first_over_time" => [:range],
      "ts_of_last_over_time" => [:range],
      "ts_of_min_over_time" => [:range],
      "ts_of_max_over_time" => [:range]
    }

    expected = call_types(name, length(args), signatures)
    valid = Enum.all?(args, &match?({:ok, _}, validate(&1)))

    if valid and expected == Enum.map(args, &type/1),
      do: validate_call(expr),
      else: {:error, :invalid_function_arguments}
  end

  defp validate({:parameter_aggregate, "count_values", group, {:string, name}, inner} = expr) do
    with true <- name != "",
         {:ok, _} <- validate({:aggregate, :sum, group, inner}),
         do: {:ok, expr},
         else: (_ -> {:error, :invalid_aggregation})
  end

  defp validate({:parameter_aggregate, "count_values", _, _, _}), do: {:error, :invalid_aggregation}

  defp validate({:parameter_aggregate, _, group, parameter, inner} = expr) do
    with {:ok, _} <- validate(parameter),
         true <- type(parameter) == :scalar,
         {:ok, _} <- validate({:aggregate, :sum, group, inner}),
         do: {:ok, expr},
         else: (_ -> {:error, :invalid_aggregation})
  end

  defp validate({:binary, op, modifiers, left, right} = expr) do
    with {:ok, _} <- validate(left),
         {:ok, _} <- validate(right),
         true <- valid_binary?(op, modifiers, type(left), type(right)),
         do: {:ok, expr},
         else: (_ -> {:error, :invalid_binary_expression})
  end

  defp validate({:aggregate, _, group, inner} = expr) do
    names =
      case group do
        nil -> []
        {:grouping, _, names} -> names
      end

    with true <- names == Enum.uniq(names) and Enum.all?(names, &label_name?/1),
         {:ok, _} <- validate(inner),
         true <- type(inner) == :vector,
         do: {:ok, expr},
         else: (_ -> {:error, :invalid_grouping})
  end

  defp validate({:function, _, range} = expr) do
    with {:ok, _} <- validate(range), do: {:ok, expr}
  end

  defp validate({:subquery, inner, window, step, _} = expr) do
    with {:ok, _} <- validate(inner),
         true <- type(inner) == :vector and positive_duration?(window) and (is_nil(step) or positive_duration?(step)) do
      {:ok, expr}
    else
      _ -> {:error, :invalid_subquery}
    end
  end

  defp validate({:range, matchers, window, _} = expr) do
    with true <- positive_duration?(window),
         :ok <- validate_matchers(matchers),
         do: {:ok, expr},
         else: (_ -> {:error, :invalid_range})
  end

  defp validate({:selector, matchers, _} = expr) do
    with :ok <- validate_matchers(matchers), do: {:ok, expr}
  end

  defp validate(_), do: {:error, :invalid_range}

  defp positive_duration?({:duration, _}), do: true
  defp positive_duration?(ns), do: ns > 0

  defp call_types(name, count, signatures) do
    case {name, count} do
      {"round", 2} ->
        [:vector, :scalar]

      {"label_join", count} when count >= 3 ->
        [:vector | List.duplicate(:string, count - 1)]

      {"histogram_quantiles", count} when count >= 3 ->
        [:vector, :string | List.duplicate(:scalar, count - 2)]

      {name, count} when name in ["sort_by_label", "sort_by_label_desc"] and count >= 1 ->
        [:vector | List.duplicate(:string, count - 1)]

      {name, 0} when name in ~w(year month day_of_month day_of_week day_of_year days_in_month hour minute) ->
        []

      _ ->
        Map.get(signatures, name)
    end
  end

  defp validate_call({:call, "label_replace", [_, {:string, dst}, _, _, {:string, regex}]} = expr) do
    cond do
      not label_name?(dst) or byte_size(regex) > 1024 -> {:error, :invalid_label_replace}
      valid_regex?(regex) -> {:ok, expr}
      true -> {:error, {:invalid_label_replace_regex, regex}}
    end
  end

  defp validate_call({:call, "label_join", [_, {:string, dst}, _ | sources]} = expr) do
    # String decoding already validates UTF-8. Label-join names use the modern
    # nonempty UTF-8 vocabulary, not the legacy identifier-only grammar.
    if dst != "" and Enum.all?(sources, fn {:string, name} -> name != "" end),
      do: {:ok, expr},
      else: {:error, :invalid_function_arguments}
  end

  defp validate_call(expr), do: {:ok, expr}

  defp valid_binary?(op, modifiers, left, right) do
    boolean = "bool" in modifiers
    matching = Enum.find(modifiers, &match?([mode, _] when mode in ["on", "ignoring"], &1))
    grouping = Enum.find(modifiers, &match?([mode | _] when mode in ["group_left", "group_right"], &1))
    names = for [_mode, names] <- modifiers, name <- names, do: name

    valid_names =
      Enum.all?(names, &label_name?/1) and
        Enum.all?(modifiers, fn
          [_, names] -> names == Enum.uniq(names)
          _ -> true
        end)

    comparisons = op in ["==", "!=", ">", "<", ">=", "<="]
    sets = op in ["and", "or", "unless"]
    # Upstream scalar-only trim reaches an unsupported scalar engine operation.
    # Reject that form at admission rather than executing an invalid operation.
    trim_valid = op not in ["</", ">/"] or left == :vector or right == :vector

    valid_names and trim_valid and valid_operator_types?(comparisons, sets, boolean, left, right) and
      valid_matching?(sets, matching, grouping, left, right)
  end

  defp valid_operator_types?(comparison?, set?, boolean?, left, right) do
    boolean_valid? = not boolean? or comparison?
    scalar_valid? = valid_scalar_comparison?(comparison?, boolean?, left, right)
    set_valid? = not set? or (left == :vector and right == :vector and not boolean?)
    left in [:scalar, :vector] and right in [:scalar, :vector] and boolean_valid? and scalar_valid? and set_valid?
  end

  defp valid_scalar_comparison?(true, false, :scalar, :scalar), do: false
  defp valid_scalar_comparison?(_, _, _, _), do: true

  defp valid_matching?(set?, matching, grouping, left, right) do
    vector_valid? = (is_nil(matching) and is_nil(grouping)) or (left == :vector and right == :vector)
    group_valid? = not set? or is_nil(grouping)
    vector_valid? and group_valid? and not overlapping_labels?(matching, grouping)
  end

  defp overlapping_labels?(["on", names], [_, include]), do: Enum.any?(include, &(&1 in names))
  defp overlapping_labels?(_, _), do: false

  defp validate_matchers(matchers) do
    valid =
      length(matchers) <= 64 and
        Enum.all?(matchers, fn {name, op, value} ->
          name != "" and String.valid?(name) and
            (op not in [:re, :nre] or valid_regex?(value))
        end)

    nonempty = valid and Enum.any?(matchers, &excludes_empty?/1)

    if valid and nonempty, do: :ok, else: {:error, :invalid_selector}
  end

  defp valid_regex?(value) do
    # The native compiler still caps both its program and DFA at 1 MiB;
    # admitting longer text does not admit unbounded regex execution state.
    byte_size(value) <= 65_536 and NIF.validate_metric_regex(value) == :ok and
      NIF.validate_metric_regex(Pulse.QueryRegex.anchor(value)) == :ok
  end

  defp excludes_empty?({_, :eq, value}), do: value != ""
  defp excludes_empty?({_, :neq, value}), do: value == ""

  defp excludes_empty?({_, op, value}) do
    if NIF.validate_metric_regex(value) == :ok do
      matched = NIF.match_metric_regex(Pulse.QueryRegex.anchor(value), "")
      if op == :re, do: not matched, else: matched
    else
      false
    end
  end

  defp label_name?(name), do: name != "" and String.valid?(name)
end
