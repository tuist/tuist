defmodule Pulse.LogQL.Parser do
  @moduledoc """
  LogQL parser.

  `parse/1` turns a LogQL string into the AST rooted under
  `Pulse.LogQL.AST.*`. Log queries return a `LogQuery`; metric queries
  return a `RangeAgg`, `VectorAgg`, `LabelReplace`, `BinaryOp`, or literal. The
  discriminator is the returned struct's module.

  The grammar covers every construct documented at
  https://grafana.com/docs/loki/latest/query/, including:

    * Stream selectors with `=`, `!=`, `=~`, `!~`.
    * Line filters: `|=`, `!=`, `|~`, `!~`, with plain strings, backtick
      strings, or `ip("cidr")`.
    * Parser stages: `json`, `logfmt`, `regexp`, `pattern`, `unpack`;
      `json` and `logfmt` accept optional label extraction lists.
    * Label filters combining string, regex, numeric, duration, and byte
      comparisons with `and`/`or` — `and`/`or` bind tighter than the
      pipeline separator.
    * `line_format`, `label_format`, `drop`, `keep`, `decolorize`.
    * `unwrap label`, `unwrap duration(label)`, `unwrap bytes(label)`.
    * Range aggregations (`rate`, `count_over_time`, …) with optional
      `[range]`, `offset`, and `@` modifiers, and the `quantile_over_time`
      leading-scalar form.
    * Vector aggregations (`sum`, `topk`, …) with `by`/`without` on
      either side of the argument list.
    * `label_replace` over metric expressions with whole-value captures.
    * Binary operators with PromQL precedence, right-associative `^`,
      unary `-`, `bool` modifier on comparisons, and `on`/`ignoring`
      matching with `group_left`/`group_right`.
    * Comments: `# ... EOL` and `// ... EOL`.

  Not accepted (deliberately, until the corresponding evaluator lands):

    * `sharding` and other query-planner hints.
  """

  import NimbleParsec

  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Limits
  alias Pulse.LogQL.Quantity
  alias Pulse.PromQL.FloatParser

  # ---------------------------------------------------------------------------
  # Public entry point
  # ---------------------------------------------------------------------------

  @spec parse(String.t()) ::
          {:ok,
           AST.LogQuery.t()
           | AST.RangeAgg.t()
           | AST.VectorAgg.t()
           | AST.LabelReplace.t()
           | AST.BinaryOp.t()
           | AST.NumberLit.t()
           | AST.VectorLit.t()}
          | {:error, term()}
  def parse(input) when is_binary(input) do
    with :ok <- Limits.input(input), do: parse_bounded(input)
  catch
    :invalid_quantity ->
      {:error, :invalid_quantity}

    :invalid_string_escape ->
      {:error, :invalid_string_escape}

    :invalid_range_placement ->
      {:error, :invalid_range_placement}

    {:invalid_error_label_comparison, name} ->
      {:error, "#{name} is a string label and cannot be compared with a typed value; use a string comparison instead"}
  end

  def parse(_), do: {:error, :query_expression_limit}

  defp parse_bounded(input) do
    case do_parse(input) do
      {:ok, [ast], "", _ctx, _line_col, _offset} ->
        with :ok <- Limits.ast(ast), do: {:ok, ast}

      {:ok, _acc, rest, _ctx, {line, col}, _offset} ->
        {:error, {line, col, {:trailing_input, String.slice(rest, 0, 40)}}}

      {:error, reason, _rest, _ctx, {line, col}, _offset} ->
        {:error, {line, col, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Whitespace and comments
  # ---------------------------------------------------------------------------

  # `#`- and `//`-prefixed comments run to end-of-line. Both forms appear in
  # LogQL in the wild despite the docs only naming `#`.
  comment =
    choice([string("#"), string("//")])
    |> ignore()
    |> repeat(utf8_char(not: ?\n))
    |> ignore()

  ws =
    repeat(
      choice([
        ignore(ascii_char([?\s, ?\t, ?\r, ?\n])),
        comment
      ])
    )

  defcombinatorp(:ws, ws)

  # ---------------------------------------------------------------------------
  # Identifiers, strings, numbers
  # ---------------------------------------------------------------------------

  # Metric names in Loki can contain colons; label names cannot. We accept the
  # more permissive form for identifiers and let the semantic layer reject
  # invalid uses. Leading char: letter or underscore.
  identifier_start = ascii_char([?a..?z, ?A..?Z, ?_])
  identifier_cont = ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?:])

  identifier =
    identifier_start
    |> repeat(identifier_cont)
    |> reduce({List, :to_string, []})

  defcombinatorp(:identifier, identifier)

  # Loki's scanner admits double-quoted and backtick strings, not character
  # literals. Escaped bytes stay bytes; Unicode escapes encode runes. Unknown
  # escapes reject, so regex backslashes must be doubled or use raw strings.
  hex_digit = ascii_char([?0..?9, ?a..?f, ?A..?F])

  escape_char =
    ignore(string("\\"))
    |> choice([
      string("a") |> replace(7),
      string("b") |> replace(8),
      string("f") |> replace(12),
      string("n") |> replace(?\n),
      string("t") |> replace(?\t),
      string("r") |> replace(?\r),
      string("v") |> replace(11),
      string("\\") |> replace(?\\),
      string("\"") |> replace(?"),
      ignore(string("x"))
      |> times(hex_digit, 2)
      |> reduce({__MODULE__, :escaped_byte, [16]}),
      times(ascii_char([?0..?7]), 3)
      |> reduce({__MODULE__, :escaped_byte, [8]}),
      choice([
        ignore(string("u")) |> times(hex_digit, 4),
        ignore(string("U")) |> times(hex_digit, 8)
      ])
      |> reduce({__MODULE__, :unicode_escape, []})
    ])

  double_string =
    ignore(string("\""))
    |> repeat(
      choice([
        escape_char,
        utf8_string([not: ?", not: ?\\, not: ?\n, not: 0], min: 1)
      ])
    )
    |> ignore(string("\""))
    |> reduce({IO, :iodata_to_binary, []})

  raw_string =
    ignore(string("`"))
    |> utf8_string([not: ?`, not: 0], min: 0)
    |> ignore(string("`"))

  string_literal = choice([raw_string, double_string])

  defcombinatorp(:string_literal, string_literal)

  @doc false
  def escaped_byte(digits, base) do
    value = List.to_integer(digits, base)
    if value > 255, do: throw(:invalid_string_escape), else: <<value>>
  end

  @doc false
  def unicode_escape(digits) do
    value = List.to_integer(digits, 16)

    cond do
      # strutil accumulates into int32; wrapped negatives take its byte branch.
      value >= 0x80000000 -> <<rem(value, 256)>>
      value > 0x10FFFF -> throw(:invalid_string_escape)
      # Prometheus strutil.Unquote passes surrogates to utf8.EncodeRune.
      # Loki therefore produces a replacement per escape, not a UTF-16 pair.
      value in 0xD800..0xDFFF -> "�"
      true -> <<value::utf8>>
    end
  end

  # Loki uses Go ParseFloat, not PromQL's integer-literal grammar: hexadecimal
  # floats require a p exponent; hexadecimal integers and 0b/0o forms reject.
  int_digits = ascii_string([?0..?9], min: 1)
  float_digits = ascii_string([?0..?9, ?_], min: 1)

  decimal =
    choice([
      float_digits |> optional(string(".") |> optional(float_digits)),
      string(".") |> concat(float_digits)
    ])
    |> optional(ascii_char([?e, ?E]) |> optional(ascii_char([?-, ?+])) |> concat(float_digits))

  hex_digits = ascii_string([?0..?9, ?a..?f, ?A..?F, ?_], min: 1)

  hexadecimal =
    choice([string("0x"), string("0X")])
    |> choice([
      hex_digits |> optional(string(".") |> optional(hex_digits)),
      string(".") |> concat(hex_digits)
    ])
    |> ascii_char([?p, ?P])
    |> optional(ascii_char([?-, ?+]))
    |> concat(float_digits)

  number_literal =
    optional(ascii_char([?-, ?+]) |> parsec(:ws))
    |> choice([hexadecimal, decimal])
    |> reduce({__MODULE__, :chars_to_number, []})

  defcombinatorp(:number_literal, number_literal)
  defcombinatorp(:unsigned_number_literal, choice([hexadecimal, decimal]) |> reduce({__MODULE__, :chars_to_number, []}))

  @doc false
  def chars_to_number(chars) do
    str = IO.iodata_to_binary(chars)

    case FloatParser.parse(str) do
      {:ok, float} ->
        case Integer.parse(str) do
          {int, ""} when int != 0 -> int
          _ -> float
        end

      :error ->
        throw(:invalid_quantity)
    end
  end

  # Keep the full token together: Loki tries model.Duration first, then Go's
  # duration converter. Parsing each component separately would admit fractional
  # days and out-of-order week/day combinations that both converters reject.
  duration_literal =
    choice([
      # A leading '-' starts Loki's duration scan even for unitless zero.
      string("-0") |> lookahead_not(utf8_char([?0..?9, ?a..?z, ?A..?Z, ?_, ?., ?µ, ?μ])),
      optional(string("-"))
      |> choice([
        int_digits |> optional(string(".") |> optional(int_digits)),
        string(".") |> concat(int_digits)
      ])
      |> utf8_string([?0..?9, ?., ?n, ?u, ?µ, ?m, ?s, ?h, ?d, ?w, ?y], min: 1)
    ])
    |> reduce({__MODULE__, :duration_token_to_ns, []})

  defcombinatorp(:duration_literal, duration_literal)

  @doc false
  def duration_token_to_ns(chars), do: chars |> IO.iodata_to_binary() |> Quantity.duration_query() |> quantity_value()

  @doc false
  def range_token_to_ns(chars), do: chars |> IO.iodata_to_binary() |> Quantity.duration_literal() |> quantity_value()

  defp quantity_value({:ok, value}), do: value
  defp quantity_value({:error, _details}), do: throw(:invalid_quantity)
  defp quantity_value(:error), do: throw(:invalid_quantity)

  # The lexer admits only these case-sensitive suffix runes, even though the
  # runtime producer converter also accepts lowercase suffixes, E, and spaces.
  byte_unit =
    choice([
      string("PiB"),
      string("Pi"),
      string("TiB"),
      string("Ti"),
      string("GiB"),
      string("Gi"),
      string("MiB"),
      string("Mi"),
      string("KiB"),
      string("Ki"),
      string("kiB"),
      string("ki"),
      string("PB"),
      string("TB"),
      string("GB"),
      string("MB"),
      string("KB"),
      string("kB"),
      string("B"),
      string("P"),
      string("T"),
      string("G"),
      string("M"),
      string("K"),
      string("k")
    ])

  bytes_literal =
    choice([
      int_digits |> optional(string(".") |> optional(int_digits)),
      string(".") |> concat(int_digits)
    ])
    |> concat(byte_unit)
    |> reduce({__MODULE__, :bytes_component_to_bytes, []})

  defcombinatorp(:bytes_literal, bytes_literal)

  @doc false
  def bytes_component_to_bytes(chars), do: chars |> IO.iodata_to_binary() |> Quantity.bytes_value() |> quantity_value()

  # ---------------------------------------------------------------------------
  # Selector
  # ---------------------------------------------------------------------------

  match_op =
    choice([
      string("=~") |> replace(:re),
      string("!~") |> replace(:nre),
      string("!=") |> replace(:neq),
      string("=") |> replace(:eq)
    ])

  matcher =
    parsec(:ws)
    |> parsec(:identifier)
    |> concat(parsec(:ws))
    |> concat(match_op)
    |> concat(parsec(:ws))
    |> parsec(:string_literal)
    |> reduce({__MODULE__, :build_matcher, []})

  @doc false
  def build_matcher([name, op, value]) do
    %AST.Matcher{name: name, op: op, value: value}
  end

  selector =
    ignore(string("{"))
    |> parsec(:ws)
    |> optional(
      matcher
      |> repeat(
        parsec(:ws)
        |> ignore(string(","))
        |> concat(matcher)
      )
    )
    |> concat(parsec(:ws))
    |> ignore(string("}"))
    |> reduce({__MODULE__, :build_selector, []})

  defcombinatorp(:selector, selector)

  @doc false
  def build_selector(matchers) do
    %AST.Selector{matchers: matchers}
  end

  # ---------------------------------------------------------------------------
  # Pipeline stages
  # ---------------------------------------------------------------------------

  # Line filter operator: order matters — `!~` before `!=`, `|~` before `|=`.
  line_filter_op =
    choice([
      string("|>") |> replace(:match_pattern),
      string("!>") |> replace(:not_match_pattern),
      string("|~") |> replace(:match_re),
      string("!~") |> replace(:not_match_re),
      string("|=") |> replace(:contains),
      string("!=") |> replace(:not_contains)
    ])

  ip_matcher =
    ignore(ascii_char([?i, ?I]) |> ascii_char([?p, ?P]))
    |> parsec(:ws)
    |> ignore(string("("))
    |> parsec(:ws)
    |> parsec(:string_literal)
    |> parsec(:ws)
    |> ignore(string(")"))
    |> unwrap_and_tag(:ip)

  line_filter_value =
    choice([
      ip_matcher,
      parsec(:string_literal) |> unwrap_and_tag(:string)
    ])

  line_filter =
    parsec(:ws)
    |> concat(line_filter_op)
    |> concat(parsec(:ws))
    |> concat(line_filter_value)
    |> repeat(
      parsec(:ws)
      |> ignore(ascii_char([?o, ?O]) |> ascii_char([?r, ?R]))
      |> lookahead_not(identifier_cont)
      |> concat(parsec(:ws))
      |> concat(line_filter_value)
    )
    |> reduce({__MODULE__, :build_line_filter, []})

  @doc false
  def build_line_filter([op | values]) do
    value =
      case Enum.map(values, &line_filter_value(op, &1)) do
        [value] -> value
        alternatives -> {:or, alternatives}
      end

    %AST.LineFilter{op: op, value: value}
  end

  # Every alternative inherits the primary operator, including its string
  # interpretation. IP retains its tag so unsupported operators still reject.
  defp line_filter_value(_, {:ip, ip}), do: {:ip, ip}

  defp line_filter_value(op, {:string, s}) when op in [:match_re, :not_match_re], do: {:re, s}

  defp line_filter_value(op, {:string, s}) when op in [:match_pattern, :not_match_pattern], do: {:pattern, s}

  defp line_filter_value(_, {:string, s}), do: {:string, s}

  # --- Label filter ---------------------------------------------------------

  cmp_op =
    choice([
      string("=~") |> replace(:re),
      string("!~") |> replace(:nre),
      string("<=") |> replace(:lte),
      string(">=") |> replace(:gte),
      string("!=") |> replace(:neq),
      string("=") |> replace(:eq),
      string("<") |> replace(:lt),
      string(">") |> replace(:gt)
    ])

  # A single label predicate. The value's tag drives evaluator dispatch, so we
  # tag every branch here rather than reconstruct at eval time.
  numeric_filter_value =
    choice([
      parsec(:duration_literal) |> unwrap_and_tag(:duration_ns),
      parsec(:bytes_literal) |> unwrap_and_tag(:bytes),
      parsec(:number_literal) |> unwrap_and_tag(:number)
    ])

  label_filter_value =
    choice([
      ip_matcher,
      numeric_filter_value,
      parsec(:string_literal) |> unwrap_and_tag(:string)
    ])

  label_cmp =
    parsec(:ws)
    |> parsec(:identifier)
    |> concat(parsec(:ws))
    |> choice([
      # Loki permits == only for typed numeric/quantity filters, not strings,
      # stream selectors or drop/keep matchers.
      string("==") |> replace(:eq) |> concat(parsec(:ws)) |> concat(numeric_filter_value),
      cmp_op |> concat(parsec(:ws)) |> concat(label_filter_value)
    ])
    |> reduce({__MODULE__, :build_label_cmp, []})

  @doc false
  def build_label_cmp([name, _op, {tag, _value}])
      when name in ["__error__", "__error_details__"] and tag in [:number, :duration_ns, :bytes, :ip] do
    # Reject at construction, including nested and post-unwrap predicates,
    # rather than deferring a syntactic type error to query evaluation.
    throw({:invalid_error_label_comparison, name})
  end

  def build_label_cmp([name, op, {tag, value}]) do
    tagged =
      cond do
        tag == :ip -> {:ip, value}
        op in [:re, :nre] -> {:re, value}
        tag == :string -> {:string, value}
        true -> {tag, value}
      end

    {:cmp, name, op, tagged}
  end

  # Explicit AND binds tighter than OR. Loki's comma/implicit conjunctions
  # instead attach the remaining expression on their right: a,b or c means
  # a AND (b OR c), while a or b,c means a OR (b AND c). Parentheses group.
  label_filter_expr =
    parsec(:label_filter_or)
    |> reduce({__MODULE__, :wrap_label_filter, []})

  @doc false
  def wrap_label_filter([expr]), do: %AST.LabelFilter{expr: expr}

  label_filter_or =
    parsec(:label_filter_and)
    |> repeat(
      parsec(:ws)
      |> ignore(ascii_char([?o, ?O]) |> ascii_char([?r, ?R]))
      |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
      |> concat(parsec(:label_filter_and))
      |> reduce({__MODULE__, :label_filter_or_pair, []})
    )
    |> reduce({__MODULE__, :fold_label_filter_left, []})

  defcombinatorp(:label_filter_or, label_filter_or)

  label_filter_and =
    parsec(:label_filter_atom)
    |> repeat(
      parsec(:ws)
      |> choice([
        ignore(ascii_char([?a, ?A]) |> ascii_char([?n, ?N]) |> ascii_char([?d, ?D]))
        |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
        |> concat(parsec(:label_filter_atom)),
        optional(ignore(string(","))) |> parsec(:label_filter_or)
      ])
      |> reduce({__MODULE__, :label_filter_and_pair, []})
    )
    |> reduce({__MODULE__, :fold_label_filter_left, []})

  defcombinatorp(:label_filter_and, label_filter_and)

  label_filter_atom =
    parsec(:ws)
    |> choice([
      ignore(string("("))
      |> parsec(:label_filter_or)
      |> concat(parsec(:ws))
      |> ignore(string(")")),
      label_cmp
    ])

  defcombinatorp(:label_filter_atom, label_filter_atom)

  @doc false
  def label_filter_or_pair([expr]), do: {:or, expr}
  @doc false
  def label_filter_and_pair([expr]), do: {:and, expr}

  @doc false
  # Left-fold the accumulator into a properly-shaped tree. First element is
  # the head; subsequent elements are `{:and, expr}` / `{:or, expr}` markers.
  def fold_label_filter_left([head | tail]) do
    Enum.reduce(tail, head, fn
      {:and, rhs}, acc -> {:and, acc, rhs}
      {:or, rhs}, acc -> {:or, acc, rhs}
    end)
  end

  # A pipeline `|` may be either a label filter or a stage. Label filters and
  # stages both start with `|`. The parser tries stages first (they name a
  # keyword), then falls back to a label filter.

  # --- Parser stages --------------------------------------------------------

  # An optional field extractor list: `label`, `label="path"`, comma-separated.
  parser_field =
    parsec(:ws)
    |> parsec(:identifier)
    |> optional(
      parsec(:ws)
      |> ignore(string("="))
      |> concat(parsec(:ws))
      |> parsec(:string_literal)
    )
    |> reduce({__MODULE__, :build_parser_field, []})

  @doc false
  def build_parser_field([name]), do: {name, name}
  def build_parser_field([name, source]), do: {name, source}

  parser_fields =
    parser_field
    |> repeat(
      parsec(:ws)
      |> ignore(string(","))
      |> concat(parser_field)
    )

  json_stage =
    ignore(string("json"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> optional(concat(parsec(:ws), parser_fields))
    |> reduce({__MODULE__, :build_json_stage, []})

  @doc false
  def build_json_stage([]), do: %AST.JsonParser{fields: []}
  def build_json_stage(fields), do: %AST.JsonParser{fields: fields}

  logfmt_flag =
    choice([
      string("--strict") |> replace(:strict),
      string("--keep-empty") |> replace(:keep_empty)
    ])

  logfmt_flags =
    parsec(:ws) |> concat(logfmt_flag) |> repeat()

  logfmt_stage =
    ignore(string("logfmt"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> concat(logfmt_flags)
    |> optional(concat(parsec(:ws), parser_fields))
    |> reduce({__MODULE__, :build_logfmt_stage, []})

  @doc false
  def build_logfmt_stage(parts) do
    {flags, fields} = Enum.split_with(parts, &is_atom/1)
    %AST.LogfmtParser{fields: fields, flags: flags}
  end

  regexp_stage =
    ignore(string("regexp"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> parsec(:string_literal)
    |> reduce({__MODULE__, :build_regexp_stage, []})

  @doc false
  def build_regexp_stage([pattern]), do: %AST.RegexpParser{pattern: pattern}

  pattern_stage =
    ignore(string("pattern"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> parsec(:string_literal)
    |> reduce({__MODULE__, :build_pattern_stage, []})

  @doc false
  def build_pattern_stage([pattern]), do: %AST.PatternParser{pattern: pattern}

  unpack_stage =
    ignore(string("unpack"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> replace(%AST.UnpackParser{})

  # --- Format stages --------------------------------------------------------

  line_format_stage =
    ignore(string("line_format"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> parsec(:string_literal)
    |> reduce({__MODULE__, :build_line_format, []})

  @doc false
  def build_line_format([template]), do: %AST.LineFormat{template: template}

  label_format_entry =
    parsec(:ws)
    |> parsec(:identifier)
    |> concat(parsec(:ws))
    |> ignore(string("="))
    |> concat(parsec(:ws))
    |> choice([
      parsec(:string_literal) |> unwrap_and_tag(:template),
      parsec(:identifier) |> unwrap_and_tag(:rename)
    ])
    |> reduce({__MODULE__, :build_label_format_entry, []})

  @doc false
  def build_label_format_entry([name, {:template, s}]), do: {name, {:template, s}}
  def build_label_format_entry([name, {:rename, other}]), do: {name, {:rename, other}}

  label_format_stage =
    ignore(string("label_format"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> concat(label_format_entry)
    |> repeat(
      parsec(:ws)
      |> ignore(string(","))
      |> concat(label_format_entry)
    )
    |> reduce({__MODULE__, :build_label_format, []})

  @doc false
  def build_label_format(entries), do: %AST.LabelFormat{entries: entries}

  # --- Drop / Keep ----------------------------------------------------------

  drop_keep_match =
    optional(
      parsec(:ws)
      |> concat(cmp_op)
      |> concat(parsec(:ws))
      |> parsec(:string_literal)
    )
    |> reduce({__MODULE__, :build_drop_match, []})

  @doc false
  def build_drop_match([]), do: :any
  def build_drop_match([:eq, v]), do: {:eq, v}
  def build_drop_match([:neq, v]), do: {:neq, v}
  def build_drop_match([:re, v]), do: {:re, v}
  def build_drop_match([:nre, v]), do: {:nre, v}

  drop_keep_entry =
    parsec(:ws)
    |> parsec(:identifier)
    |> concat(drop_keep_match)
    |> reduce({__MODULE__, :build_drop_entry, []})

  @doc false
  def build_drop_entry([name, match]), do: {name, match}

  drop_stage =
    ignore(string("drop"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> concat(drop_keep_entry)
    |> repeat(
      parsec(:ws)
      |> ignore(string(","))
      |> concat(drop_keep_entry)
    )
    |> reduce({__MODULE__, :build_drop_stage, []})

  @doc false
  def build_drop_stage(entries), do: %AST.Drop{entries: entries}

  keep_stage =
    ignore(string("keep"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> concat(drop_keep_entry)
    |> repeat(
      parsec(:ws)
      |> ignore(string(","))
      |> concat(drop_keep_entry)
    )
    |> reduce({__MODULE__, :build_keep_stage, []})

  @doc false
  def build_keep_stage(entries), do: %AST.Keep{entries: entries}

  decolorize_stage =
    ignore(string("decolorize"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> replace(%AST.Decolorize{})

  # --- Unwrap ---------------------------------------------------------------

  unwrap_conversion =
    choice([
      string("duration_seconds") |> replace(:duration_seconds),
      string("duration") |> replace(:duration),
      string("bytes") |> replace(:bytes)
    ])

  unwrap_stage =
    ignore(string("unwrap"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> choice([
      unwrap_conversion
      |> ignore(string("("))
      |> parsec(:ws)
      |> parsec(:identifier)
      |> parsec(:ws)
      |> ignore(string(")"))
      |> reduce({__MODULE__, :build_unwrap_conv, []}),
      parsec(:identifier) |> reduce({__MODULE__, :build_unwrap_plain, []})
    ])

  @doc false
  def build_unwrap_conv([conv, label]), do: %AST.Unwrap{label: label, conversion: conv}
  @doc false
  def build_unwrap_plain([label]), do: %AST.Unwrap{label: label, conversion: :none}

  # A pipe-prefixed stage. Try named stages first, then fall back to a label
  # filter — a label filter begins with an identifier followed by a comparison
  # operator, which none of the named stages match.
  pipe_stage =
    parsec(:ws)
    |> ignore(string("|"))
    |> parsec(:ws)
    |> choice([
      json_stage,
      logfmt_stage,
      regexp_stage,
      pattern_stage,
      unpack_stage,
      line_format_stage,
      label_format_stage,
      drop_stage,
      keep_stage,
      decolorize_stage,
      unwrap_stage,
      parsec(:label_filter_expr)
    ])

  defcombinatorp(:label_filter_expr, label_filter_expr)

  # Standalone (non-pipe-prefixed) filter forms that follow the selector
  # without a leading `|`: `|=`, `!=`, `|~`, `!~`.
  bare_line_filter =
    parsec(:ws)
    |> concat(line_filter)

  pipeline_stage = choice([pipe_stage, bare_line_filter])

  defcombinatorp(:pipeline_stage, pipeline_stage)

  # ---------------------------------------------------------------------------
  # Log query
  # ---------------------------------------------------------------------------

  log_query =
    parsec(:ws)
    |> parsec(:selector)
    |> repeat(parsec(:pipeline_stage))
    |> reduce({__MODULE__, :build_log_query, []})

  defcombinatorp(:log_query, log_query)

  @doc false
  def build_log_query([%AST.Selector{} = selector | stages]) do
    %AST.LogQuery{selector: selector, stages: stages}
  end

  # ---------------------------------------------------------------------------
  # Metric expression
  # ---------------------------------------------------------------------------

  range_agg_name =
    choice([
      string("rate_counter") |> replace(:rate_counter),
      string("rate") |> replace(:rate),
      string("count_over_time") |> replace(:count_over_time),
      string("approx_count_distinct") |> replace(:approx_count_distinct),
      string("bytes_over_time") |> replace(:bytes_over_time),
      string("bytes_rate") |> replace(:bytes_rate),
      string("sum_over_time") |> replace(:sum_over_time),
      string("avg_over_time") |> replace(:avg_over_time),
      string("max_over_time") |> replace(:max_over_time),
      string("min_over_time") |> replace(:min_over_time),
      string("stddev_over_time") |> replace(:stddev_over_time),
      string("stdvar_over_time") |> replace(:stdvar_over_time),
      string("quantile_over_time") |> replace(:quantile_over_time),
      string("first_over_time") |> replace(:first_over_time),
      string("last_over_time") |> replace(:last_over_time),
      string("absent_over_time") |> replace(:absent_over_time)
    ])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  vector_agg_name =
    choice([
      string("sum") |> replace(:sum),
      string("avg") |> replace(:avg),
      string("min") |> replace(:min),
      string("max") |> replace(:max),
      string("count") |> replace(:count),
      string("stddev") |> replace(:stddev),
      string("stdvar") |> replace(:stdvar),
      string("topk") |> replace(:topk),
      string("approx_topk") |> replace(:approx_topk),
      string("bottomk") |> replace(:bottomk),
      string("sort_desc") |> replace(:sort_desc),
      string("sort") |> replace(:sort)
    ])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  identifier_list =
    parsec(:identifier)
    |> repeat(
      parsec(:ws)
      |> ignore(string(","))
      |> concat(parsec(:ws))
      |> parsec(:identifier)
    )

  grouping =
    parsec(:ws)
    |> choice([
      string("by") |> replace(:by),
      string("without") |> replace(:without)
    ])
    |> concat(parsec(:ws))
    |> ignore(string("("))
    |> parsec(:ws)
    |> optional(identifier_list)
    |> parsec(:ws)
    |> ignore(string(")"))
    |> reduce({__MODULE__, :build_grouping, []})

  @doc false
  def build_grouping([mode | labels]) do
    %AST.Grouping{mode: mode, labels: labels}
  end

  offset_modifier =
    parsec(:ws)
    |> ignore(string("offset"))
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> parsec(:ws)
    |> parsec(:duration_literal)
    |> unwrap_and_tag(:offset)

  at_modifier =
    parsec(:ws)
    |> ignore(string("@"))
    |> parsec(:ws)
    |> parsec(:number_literal)
    |> unwrap_and_tag(:at)

  # `[duration]` bracket. Kept as its own combinator so `unwrap_and_tag(:range)`
  # sees only `[duration]` — the surrounding brackets and whitespace emit no
  # tokens.
  range_bracket =
    parsec(:ws)
    |> ignore(string("["))
    |> ascii_string([?0..?9, ?a..?z], min: 1)
    |> reduce({__MODULE__, :range_token_to_ns, []})
    |> ignore(string("]"))
    |> unwrap_and_tag(:range)

  # Loki's range parameter is a NUMBER token, not a signed scalar expression.
  # Signs inside exponents remain part of the token. Validation checks which
  # parameter type the chosen operator accepts.
  range_leading_param =
    choice([parsec(:unsigned_number_literal), parsec(:identifier)])
    |> unwrap_and_tag(:param)
    |> parsec(:ws)
    |> ignore(string(","))

  # Loki permits the pipeline before or after the range/offset, parentheses
  # around the source, and recursively wrapped whole ranges. Source parentheses
  # permit only a trailing unwrap, not a new parser pipeline after the bracket.
  range_source =
    choice([
      parsec(:log_query),
      ignore(string("("))
      |> parsec(:log_query)
      |> parsec(:ws)
      |> ignore(string(")"))
      |> unwrap_and_tag(:parenthesized_source)
    ])

  range_primary =
    range_source
    |> concat(range_bracket)
    |> optional(offset_modifier)
    |> optional(at_modifier)
    |> repeat(parsec(:pipeline_stage))
    |> reduce({__MODULE__, :build_log_range, []})

  defcombinatorp(
    :log_range,
    choice([
      range_primary,
      ignore(string("("))
      |> parsec(:ws)
      |> parsec(:log_range)
      |> parsec(:ws)
      |> ignore(string(")"))
    ])
  )

  @doc false
  def build_log_range(parts) do
    {prefix, stages} = Enum.split_while(parts, &(not is_struct(&1) or match?(%AST.LogQuery{}, &1)))
    wrapped? = Enum.any?(prefix, &match?({:parenthesized_source, _}, &1))

    body =
      Enum.reduce(prefix, %{range: nil, offset: nil, at: nil, inner: nil}, fn
        {:range, r}, acc -> %{acc | range: r}
        {:offset, o}, acc -> %{acc | offset: o}
        {:at, a}, acc -> %{acc | at: trunc(a * 1_000_000_000)}
        {:parenthesized_source, q}, acc -> %{acc | inner: q}
        %AST.LogQuery{} = q, acc -> %{acc | inner: q}
      end)

    case {body.inner.stages, stages, wrapped?} do
      {_, [], _} -> :ok
      {[], [%AST.Unwrap{} | _], _} -> :ok
      {[], _, false} -> :ok
      _ -> throw(:invalid_range_placement)
    end

    %{body | inner: %{body.inner | stages: body.inner.stages ++ stages}}
  end

  range_body =
    parsec(:ws)
    |> optional(range_leading_param)
    |> parsec(:ws)
    |> parsec(:log_range)
    |> reduce({__MODULE__, :build_range_body, []})

  @doc false
  def build_range_body(parts) do
    Enum.reduce(parts, %{param: nil, range: nil, offset: nil, at: nil, inner: nil}, fn
      {:param, p}, acc -> %{acc | param: p}
      range, acc -> Map.merge(acc, range)
    end)
  end

  range_agg =
    range_agg_name
    |> concat(parsec(:ws))
    |> ignore(string("("))
    |> concat(range_body)
    |> concat(parsec(:ws))
    |> ignore(string(")"))
    |> optional(grouping)
    |> reduce({__MODULE__, :build_range_agg, []})

  @doc false
  def build_range_agg([op, body]), do: build_range_agg([op, body, nil])

  def build_range_agg([op, body, grouping]) do
    %AST.RangeAgg{
      op: op,
      inner: body.inner,
      range_ns: body.range,
      offset_ns: body.offset,
      at_ns: body.at,
      param: body.param,
      grouping: grouping
    }
  end

  # Vector aggregator: `sum(...)`, `sum by (svc)(...)`, `sum(...) by (svc)`,
  # `topk(5, ...)` — the scalar param appears before the vector expression.
  vector_agg_call_body =
    parsec(:ws)
    |> ignore(string("("))
    |> parsec(:ws)
    |> optional(
      parsec(:number_literal)
      |> unwrap_and_tag(:param)
      |> concat(parsec(:ws))
      |> ignore(string(","))
    )
    |> parsec(:ws)
    |> concat(parsec(:metric_expr))
    |> concat(parsec(:ws))
    |> ignore(string(")"))
    |> reduce({__MODULE__, :build_vector_call_body, []})

  @doc false
  def build_vector_call_body(parts) do
    Enum.reduce(parts, %{param: nil, inner: nil}, fn
      {:param, p}, acc -> %{acc | param: p}
      inner, acc -> %{acc | inner: inner}
    end)
  end

  vector_agg =
    vector_agg_name
    |> concat(
      choice([
        grouping
        |> concat(vector_agg_call_body)
        |> reduce({__MODULE__, :build_vector_agg_pre_grouping, []}),
        vector_agg_call_body
        |> optional(grouping)
        |> reduce({__MODULE__, :build_vector_agg_post_grouping, []})
      ])
    )
    |> reduce({__MODULE__, :attach_vector_op, []})

  @doc false
  def build_vector_agg_pre_grouping([grouping, body]) do
    %{grouping: grouping, body: body}
  end

  def build_vector_agg_post_grouping([body]) do
    %{grouping: nil, body: body}
  end

  def build_vector_agg_post_grouping([body, grouping]) do
    %{grouping: grouping, body: body}
  end

  @doc false
  def attach_vector_op([op, %{grouping: grouping, body: body}]) do
    # Preserve integer syntax for approx_topk; other aggregations retain their
    # existing normalization of integral float parameters.
    param = body.param
    param = if op != :approx_topk and is_number(param) and param == trunc(param), do: trunc(param), else: param
    %AST.VectorAgg{op: op, inner: body.inner, grouping: grouping, param: param}
  end

  # ---------------------------------------------------------------------------
  # Metric expression with operator precedence
  # ---------------------------------------------------------------------------

  # PromQL precedence, low to high:
  #   or
  #   and, unless
  #   ==, !=, <=, <, >=, >
  #   +, -
  #   *, /, %
  #   ^ (right-assoc)
  #   unary -
  #   atom

  metric_expr =
    parsec(:or_expr)

  defcombinatorp(:metric_expr, metric_expr)

  or_expr =
    parsec(:and_expr)
    |> repeat(
      parsec(:ws)
      |> ignore(string("or"))
      |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
      |> optional(parsec(:vector_matching))
      |> concat(parsec(:and_expr))
      |> reduce({__MODULE__, :binop_marker, [:or]})
    )
    |> reduce({__MODULE__, :fold_binop_left, []})

  defcombinatorp(:or_expr, or_expr)

  and_expr =
    parsec(:cmp_expr)
    |> repeat(
      parsec(:ws)
      |> choice([
        string("and") |> replace(:and),
        string("unless") |> replace(:unless)
      ])
      |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
      |> optional(parsec(:vector_matching))
      |> concat(parsec(:cmp_expr))
      |> reduce({__MODULE__, :binop_marker_dyn, []})
    )
    |> reduce({__MODULE__, :fold_binop_left, []})

  defcombinatorp(:and_expr, and_expr)

  cmp_op_atom =
    choice([
      string("==") |> replace(:eq),
      string("!=") |> replace(:neq),
      string("<=") |> replace(:lte),
      string(">=") |> replace(:gte),
      string("<") |> replace(:lt),
      string(">") |> replace(:gt)
    ])

  cmp_expr =
    parsec(:add_expr)
    |> repeat(
      parsec(:ws)
      |> concat(cmp_op_atom)
      |> optional(
        parsec(:ws)
        |> string("bool")
        |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
        |> replace(:bool)
      )
      |> optional(parsec(:vector_matching))
      |> concat(parsec(:add_expr))
      |> reduce({__MODULE__, :binop_marker_cmp, []})
    )
    |> reduce({__MODULE__, :fold_binop_left, []})

  defcombinatorp(:cmp_expr, cmp_expr)

  add_expr =
    parsec(:mul_expr)
    |> repeat(
      parsec(:ws)
      |> choice([
        string("+") |> replace(:add),
        string("-") |> replace(:sub)
      ])
      |> optional(parsec(:vector_matching))
      |> concat(parsec(:mul_expr))
      |> reduce({__MODULE__, :binop_marker_dyn, []})
    )
    |> reduce({__MODULE__, :fold_binop_left, []})

  defcombinatorp(:add_expr, add_expr)

  mul_expr =
    parsec(:pow_expr)
    |> repeat(
      parsec(:ws)
      |> choice([
        string("*") |> replace(:mul),
        string("/") |> replace(:div),
        string("%") |> replace(:mod)
      ])
      |> optional(parsec(:vector_matching))
      |> concat(parsec(:pow_expr))
      |> reduce({__MODULE__, :binop_marker_dyn, []})
    )
    |> reduce({__MODULE__, :fold_binop_left, []})

  defcombinatorp(:mul_expr, mul_expr)

  # `^` is right-associative, so recurse right rather than fold left.
  pow_expr =
    parsec(:unary_expr)
    |> optional(
      parsec(:ws)
      |> ignore(string("^"))
      |> optional(parsec(:vector_matching))
      |> concat(parsec(:pow_expr))
      |> reduce({__MODULE__, :pow_marker, []})
    )
    |> reduce({__MODULE__, :fold_pow_right, []})

  defcombinatorp(:pow_expr, pow_expr)

  @doc false
  def pow_marker([%AST.VectorMatching{} = m, rhs]), do: {:pow, m, rhs}
  def pow_marker([rhs]), do: {:pow, nil, rhs}

  @doc false
  def fold_pow_right([lhs]), do: lhs

  def fold_pow_right([lhs, {:pow, matching, rhs}]) do
    %AST.BinaryOp{op: :pow, left: lhs, right: rhs, matching: matching}
  end

  # A sign belongs to NUMBER only; unlike PromQL it cannot negate a vector or
  # parenthesized expression. It binds before exponentiation: -2^2 == 4.
  defcombinatorp(:unary_expr, parsec(:atom_expr))

  label_replace =
    ignore(string("label_replace"))
    |> parsec(:ws)
    |> ignore(string("("))
    |> parsec(:metric_expr)
    |> times(
      parsec(:ws)
      |> ignore(string(","))
      |> parsec(:ws)
      |> parsec(:string_literal),
      4
    )
    |> parsec(:ws)
    |> ignore(string(")"))
    |> reduce({__MODULE__, :build_label_replace, []})

  @doc false
  def build_label_replace([inner, dst, replacement, src, regex]) do
    %AST.LabelReplace{inner: inner, dst: dst, replacement: replacement, src: src, regex: regex}
  end

  # `atom` in metric context: range agg, vector agg, number literal, or a
  # parenthesized metric expression. A bare `{selector}...` also counts as a
  # metric-context atom only when it appears inside a range-agg body; at the
  # top level a log query returns from `parse/1` on its own.
  atom_expr =
    parsec(:ws)
    |> choice([
      range_agg,
      vector_agg,
      label_replace,
      ignore(string("("))
      |> parsec(:metric_expr)
      |> concat(parsec(:ws))
      |> ignore(string(")")),
      ignore(string("vector"))
      |> concat(parsec(:ws))
      |> ignore(string("("))
      |> concat(parsec(:ws))
      |> parsec(:number_literal)
      |> concat(parsec(:ws))
      |> ignore(string(")"))
      |> map({__MODULE__, :wrap_vector, []}),
      parsec(:number_literal) |> map({__MODULE__, :wrap_number, []})
    ])

  defcombinatorp(:atom_expr, atom_expr)

  @doc false
  def wrap_number(n), do: %AST.NumberLit{value: n}

  @doc false
  def wrap_vector(n), do: %AST.VectorLit{value: n}

  # --- Vector matching modifier --------------------------------------------

  match_mode =
    choice([
      string("on") |> replace(:on),
      string("ignoring") |> replace(:ignoring)
    ])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  group_side =
    choice([
      string("group_left") |> replace(:left),
      string("group_right") |> replace(:right)
    ])
    |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))

  vector_matching =
    parsec(:ws)
    |> concat(match_mode)
    |> concat(parsec(:ws))
    |> ignore(string("("))
    |> parsec(:ws)
    |> optional(identifier_list)
    |> parsec(:ws)
    |> ignore(string(")"))
    |> optional(
      parsec(:ws)
      |> concat(group_side)
      |> optional(
        parsec(:ws)
        |> ignore(string("("))
        |> parsec(:ws)
        |> optional(identifier_list)
        |> parsec(:ws)
        |> ignore(string(")"))
        |> reduce({__MODULE__, :collect_group_labels, []})
      )
      |> reduce({__MODULE__, :collect_group_side, []})
    )
    |> reduce({__MODULE__, :build_vector_matching, []})

  defcombinatorp(:vector_matching, vector_matching)

  @doc false
  def collect_group_labels(labels), do: {:group_labels, labels}

  @doc false
  def collect_group_side([side]), do: {:group, side, []}
  def collect_group_side([side, {:group_labels, labels}]), do: {:group, side, labels}

  @doc false
  def build_vector_matching([mode | rest]) do
    {labels, group_info} =
      case rest do
        [{:group, side, group_labels}] ->
          {[], {side, group_labels}}

        labels ->
          case Enum.split_while(labels, &is_binary/1) do
            {ls, []} -> {ls, nil}
            {ls, [{:group, side, glabels}]} -> {ls, {side, glabels}}
          end
      end

    base = %AST.VectorMatching{mode: mode, labels: labels}

    case group_info do
      nil -> base
      {side, glabels} -> %{base | group: side, group_labels: glabels}
    end
  end

  # --- BinaryOp folding -----------------------------------------------------

  # Each `_marker` helper returns a compact structure that `fold_binop_left`
  # then reduces into a `%BinaryOp{}`.

  @doc false
  def binop_marker([%AST.VectorMatching{} = m, rhs], op), do: {op, false, m, rhs}
  def binop_marker([rhs], op), do: {op, false, nil, rhs}

  @doc false
  def binop_marker_dyn([op, %AST.VectorMatching{} = m, rhs]), do: {op, false, m, rhs}
  def binop_marker_dyn([op, rhs]), do: {op, false, nil, rhs}

  @doc false
  def binop_marker_cmp([op, :bool, %AST.VectorMatching{} = m, rhs]), do: {op, true, m, rhs}
  def binop_marker_cmp([op, :bool, rhs]), do: {op, true, nil, rhs}
  def binop_marker_cmp([op, %AST.VectorMatching{} = m, rhs]), do: {op, false, m, rhs}
  def binop_marker_cmp([op, rhs]), do: {op, false, nil, rhs}

  @doc false
  def fold_binop_left([lhs | rest]) do
    Enum.reduce(rest, lhs, fn {op, bool, matching, rhs}, acc ->
      %AST.BinaryOp{op: op, left: acc, right: rhs, bool: bool, matching: matching}
    end)
  end

  # ---------------------------------------------------------------------------
  # Top-level dispatch
  # ---------------------------------------------------------------------------

  # A top-level expression is either a metric expression or a bare log query.
  # We try the metric expression first because it also accepts numbers and
  # parenthesized forms; if it succeeds but leaves a selector unconsumed the
  # log-query branch will run instead.
  expression =
    parsec(:ws)
    |> choice([
      parsec(:metric_expr),
      parsec(:log_query)
    ])
    |> concat(parsec(:ws))

  defparsecp(:do_parse, expression)
end
