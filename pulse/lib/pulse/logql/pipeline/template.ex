defmodule Pulse.LogQL.Pipeline.Template do
  @moduledoc false

  alias Pulse.Codec.NIF
  alias Pulse.GoUnicode
  alias Pulse.LogQL.Pipeline.TemplateJSON
  alias Pulse.LogQL.Quantity
  alias Pulse.PromQL.Evaluator
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number

  # A deliberately closed subset of text/template. Unknown syntax/functions
  # reject during admission, rather than silently producing an empty string.
  @functions %{
    "upper" => 1,
    "ToUpper" => 1,
    "lower" => 1,
    "ToLower" => 1,
    "trim" => 1,
    "TrimSpace" => 1,
    "trimAll" => 2,
    "Trim" => 2,
    "TrimLeft" => 2,
    "TrimRight" => 2,
    "replace" => 3,
    "Replace" => 4,
    "repeat" => 2,
    "indent" => 2,
    "nindent" => 2,
    "alignLeft" => 2,
    "alignRight" => 2,
    "trunc" => 2,
    "substr" => 3,
    "title" => 1,
    "urlencode" => 1,
    "urldecode" => 1,
    "b64enc" => 1,
    "b64dec" => 1,
    "trimPrefix" => 2,
    "trimSuffix" => 2,
    "TrimPrefix" => 2,
    "TrimSuffix" => 2,
    "contains" => 2,
    "hasPrefix" => 2,
    "hasSuffix" => 2,
    "default" => 2,
    "and" => {:min, 1},
    "or" => {:min, 1},
    "not" => 1,
    "eq" => {:min, 2},
    "ne" => 2,
    "lt" => 2,
    "le" => 2,
    "gt" => 2,
    "ge" => 2,
    "len" => 1,
    "index" => {:min, 1},
    "slice" => {:min, 1},
    "print" => {:min, 0},
    "println" => {:min, 0},
    "html" => {:min, 0},
    "js" => {:min, 0},
    "urlquery" => {:min, 0},
    "int" => 1,
    "add" => {:min, 0},
    "sub" => 2,
    "mul" => {:min, 1},
    "div" => 2,
    "mod" => 2,
    "min" => {:min, 1},
    "max" => {:min, 1},
    "float64" => 1,
    "minf" => {:min, 1},
    "maxf" => {:min, 1},
    "floor" => 1,
    "ceil" => 1,
    "round" => {:min, 2},
    "addf" => {:min, 0},
    "subf" => {:min, 1},
    "mulf" => {:min, 1},
    "divf" => {:min, 1},
    "bytes" => 1,
    "duration" => 1,
    "duration_seconds" => 1,
    "fromJson" => 1,
    "count" => 2,
    "regexReplaceAll" => 3,
    "regexReplaceAllLiteral" => 3,
    "__line__" => 0,
    "__timestamp__" => 0,
    "unixToTime" => 1,
    "unixEpoch" => 1,
    "unixEpochMillis" => 1,
    "unixEpochNanos" => 1
  }
  @max_output_bytes 16_777_216
  @html_escapes %{"\0" => "�", "\"" => "&#34;", "'" => "&#39;", "&" => "&amp;", "<" => "&lt;", ">" => "&gt;"}
  @js_escapes %{
    ?\\ => "\\\\",
    ?' => "\\'",
    ?" => "\\\"",
    ?< => "\\u003C",
    ?> => "\\u003E",
    ?& => "\\u0026",
    ?= => "\\u003D"
  }
  @js_special ~r/[\x00-\x1f\\"'<>&=\x{80}-\x{10ffff}]/u
  @space ~r/\A[\x09-\x0d\x20\x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}]+|[\x09-\x0d\x20\x{85}\x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}]+\z/u
  @integer "[+-]?(?:0[xX]_?[0-9a-fA-F](?:_?[0-9a-fA-F])*|0[bB]_?[01](?:_?[01])*|0[oO]?_?[0-7](?:_?[0-7])*|[1-9](?:_?[0-9])*|0)"
  @number_token ~r/\A[^\s|(){}]+/
  @integer_cast Regex.compile!("\\A#{@integer}\\z")
  @integer_arguments %{
    "Replace" => [3],
    "repeat" => [0],
    "indent" => [0],
    "nindent" => [0],
    "alignLeft" => [0],
    "alignRight" => [0],
    "trunc" => [0],
    "substr" => [0, 1],
    "round" => [1]
  }

  def compile(str) when is_binary(str) do
    case compile_text(str, [], 0, MapSet.new(["$"])) do
      {nodes, "", :eof, _variables} -> {:ok, nodes}
      _ -> invalid("unexpected template control action")
    end
  catch
    {:template_error, details} -> {:error, details}
  end

  defp compile_text(_rest, _acc, depth, _variables) when depth > 64, do: invalid("template nesting limit")
  defp compile_text("", acc, _depth, variables), do: {Enum.reverse(acc), "", :eof, variables}

  defp compile_text(rest, acc, depth, variables) do
    case :binary.match(rest, "{{") do
      :nomatch ->
        {Enum.reverse([{:literal, rest} | acc]), "", :eof, variables}

      {pos, 2} ->
        <<literal::binary-size(^pos), "{{", action::binary>> = rest
        {literal, action} = trim_open(literal, action)
        compile_open(action, [{:literal, literal} | acc], depth, variables)
    end
  end

  # Trim only source text adjacent to a delimiter, never rendered values or
  # Unicode whitespace. A negative integer is not an opening trim marker.
  defp trim_open(literal, <<"-", char, rest::binary>>) when char in [32, 9, 10, 13],
    do: {trim_trailing(literal, byte_size(literal)), rest}

  defp trim_open(literal, action), do: {literal, action}

  defp trim_trailing(_text, 0), do: ""

  defp trim_trailing(text, size) do
    if :binary.at(text, size - 1) in [32, 9, 10, 13],
      do: trim_trailing(text, size - 1),
      else: binary_part(text, 0, size)
  end

  defp compile_open("/*" <> rest, acc, depth, variables), do: compile_text(comment(rest), acc, depth, variables)

  defp compile_open(action, acc, depth, variables) do
    {tokens, tail} = lex(action, [])
    compile_action(tokens, tail, acc, depth, variables)
  end

  defp comment(rest) do
    case :binary.match(rest, "*/") do
      {pos, 2} ->
        <<_::binary-size(^pos), "*/", tail::binary>> = rest
        comment_end(tail)

      :nomatch ->
        invalid("unclosed comment")
    end
  end

  defp comment_end("}}" <> tail), do: tail
  defp comment_end(<<char, "-}}", tail::binary>>) when char in [32, 9, 10, 13], do: trim_leading(tail)
  defp comment_end(_), do: invalid("comment ends before closing delimiter")

  defp trim_leading(<<char, rest::binary>>) when char in [32, 9, 10, 13], do: trim_leading(rest)
  defp trim_leading(rest), do: rest

  defp compile_action([{:control, kind} | tokens], tail, acc, depth, variables) when kind in ["if", "with"] do
    {node, tail} = compile_branch(kind, tokens, tail, depth + 1, variables)
    compile_text(tail, [node | acc], depth, variables)
  end

  defp compile_action([{:control, "range"} | tokens], tail, acc, depth, variables) do
    {header, scoped} = compile_range_header(tokens, depth + 1, variables)
    {yes, tail, terminator, scoped} = compile_text(tail, [], depth + 1, MapSet.put(scoped, :range))
    scoped = if MapSet.member?(variables, :range), do: scoped, else: MapSet.delete(scoped, :range)
    {no, tail} = compile_else(terminator, tail, depth + 1, "range", scoped)
    compile_text(tail, [{:range, header, yes, no} | acc], depth, variables)
  end

  defp compile_action([{:control, name}], tail, acc, depth, variables) when name in ["break", "continue"] do
    if not MapSet.member?(variables, :range), do: invalid("#{name} outside range")
    compile_text(tail, [if(name == "break", do: :break, else: :continue) | acc], depth, variables)
  end

  defp compile_action([{:control, "else"}, {:control, kind} | tokens], tail, acc, _depth, variables)
       when kind in ["if", "with"], do: {Enum.reverse(acc), tail, {:else_branch, kind, tokens}, variables}

  defp compile_action([{:control, name}], tail, acc, _depth, variables) when name in ["else", "end"],
    do: {Enum.reverse(acc), tail, name, variables}

  defp compile_action(tokens, tail, acc, depth, variables) do
    {node, variables} = compile_pipeline(tokens, depth, variables)
    compile_text(tail, [node | acc], depth, variables)
  end

  defp compile_pipeline(tokens, depth, variables) do
    case pipeline(tokens, depth, variables) do
      {node, [], variables} -> {node, variables}
      _ -> invalid("unexpected closing parenthesis")
    end
  end

  defp compile_range_header([{:variable, first}, ?,, {:variable, second}, binding | tokens], depth, variables)
       when binding in [:declare, :assign],
       do: compile_range_binding(tokens, binding, [first, second], depth, variables)

  defp compile_range_header([{:variable, name}, binding | tokens], depth, variables)
       when binding in [:declare, :assign], do: compile_range_binding(tokens, binding, [name], depth, variables)

  defp compile_range_header(tokens, depth, variables) do
    {node, variables} = compile_pipeline(tokens, depth, variables)
    {{nil, [], node}, variables}
  end

  defp compile_range_binding(tokens, binding, names, depth, variables) do
    variables = Enum.reduce(names, variables, &MapSet.put(&2, &1))
    {node, variables} = compile_pipeline(tokens, depth, variables)
    {{binding, names, node}, variables}
  end

  defp compile_branch(kind, tokens, tail, depth, variables) do
    {condition, variables} = compile_pipeline(tokens, depth, variables)
    # The parser sees declarations in the yes branch while parsing else too,
    # even when execution will not establish those bindings.
    {yes, tail, terminator, variables} = compile_text(tail, [], depth, variables)
    {no, tail} = compile_else(terminator, tail, depth, kind, variables)
    tag = if kind == "if", do: :if, else: :with
    {{tag, condition, yes, no}, tail}
  end

  defp compile_else("end", tail, _depth, _kind, _variables), do: {[], tail}

  defp compile_else("else", tail, depth, _kind, variables) do
    case compile_text(tail, [], depth, variables) do
      {nodes, tail, "end", _variables} -> {nodes, tail}
      _ -> invalid("expected end after else")
    end
  end

  defp compile_else({:else_branch, kind, tokens}, tail, depth, kind, variables) do
    {node, tail} = compile_branch(kind, tokens, tail, depth + 1, variables)
    {[node], tail}
  end

  defp compile_else(_, _, _, _, _), do: invalid("unclosed or mismatched template branch")

  defp lex("", _acc), do: invalid("unclosed action")
  defp lex(<<"}}", rest::binary>>, acc), do: {Enum.reverse(acc), rest}
  defp lex(<<char, "-}}", rest::binary>>, acc) when char in [32, 9, 10, 13], do: {Enum.reverse(acc), trim_leading(rest)}

  defp lex(<<char, rest::binary>>, acc) when char in [32, 9, 10, 13], do: lex(rest, acc)

  defp lex(<<").", rest::binary>>, acc) do
    case Regex.run(~r/\A(\.[\p{L}_][\p{L}\p{Nd}_]*(?:\.[\p{L}_][\p{L}\p{Nd}_]*)*)(?=[\s|(){}]|\z)/u, "." <> rest) do
      [word, _] ->
        tail = binary_part(rest, byte_size(word) - 1, byte_size(rest) - byte_size(word) + 1)
        fields = word |> String.trim_leading(".") |> String.split(".")
        lex(tail, [{:fields, fields}, ?) | acc])

      _ ->
        invalid("invalid field chain")
    end
  end

  defp lex(<<char, rest::binary>>, acc) when char in [?|, ?(, ?), ?,], do: lex(rest, [char | acc])
  defp lex(<<":=", rest::binary>>, acc), do: lex(rest, [:declare | acc])
  defp lex(<<"=", rest::binary>>, acc), do: lex(rest, [:assign | acc])

  defp lex(<<"'", source::binary>>, acc) do
    {value, rest} = character(source)

    case rest do
      <<"'.", _rest::binary>> -> invalid("unexpected field after literal")
      <<"'", rest::binary>> -> lex(rest, [{:value, value} | acc])
      _ -> invalid("malformed character constant")
    end
  end

  defp lex(<<quote, rest::binary>>, acc) when quote in [?", ?`] do
    {value, rest} = quoted(rest, quote, [])
    # Raw Go byte strings need byte-aware JSON/regex handling downstream.
    # Do not admit a template that can create invalid UTF-8 in this pipeline.
    if not String.valid?(value), do: invalid("non-UTF-8 template literals are unsupported")
    if String.starts_with?(rest, "."), do: invalid("unexpected field after literal")
    lex(rest, [{:value, value} | acc])
  end

  defp lex(<<char, _::binary>> = source, acc) when char in ?0..?9 or char in [?+, ?-] do
    lex_number(source, acc)
  end

  defp lex(<<".", digit, _::binary>> = source, acc) when digit in ?0..?9, do: lex_number(source, acc)

  defp lex(source, acc) do
    case Regex.run(
           ~r/\A(\$[\p{L}\p{Nd}_]*(?:\.[\p{L}_][\p{L}\p{Nd}_]*)*|\.?[\p{L}_][\p{L}\p{Nd}_]*(?:\.[\p{L}_][\p{L}\p{Nd}_]*)*|\.)(?=[\s|(){}:=,]|\z)/u,
           source
         ) do
      [word, _] ->
        rest = binary_part(source, byte_size(word), byte_size(source) - byte_size(word))
        lex(rest, [operand(word) | acc])

      _ ->
        invalid("unsupported template operand")
    end
  end

  defp lex_number(source, acc) do
    [number] = Regex.run(@number_token, source)
    rest = binary_part(source, byte_size(number), byte_size(source) - byte_size(number))

    value =
      cond do
        String.ends_with?(number, "i") ->
          complex(number)

        Regex.match?(@integer_cast, number) ->
          integer(number)

        not String.contains?(number, [".", "e", "E", "p", "P"]) ->
          invalid("invalid template number")

        true ->
          case FloatParser.parse(number) do
            {:ok, value} when is_float(value) -> {:float_literal, value}
            _ -> invalid("invalid template number")
          end
      end

    lex(rest, [{:value, value} | acc])
  end

  # Both components use floating syntax: 073i means 73i, not octal 59i.
  # Exponent signs are not separators; combined constants need exactly one
  # real/imaginary separator and cannot contain an earlier imaginary suffix.
  defp complex(number) do
    case Regex.run(~r/\A(.+?)(?<![eEpP])([+-].+)i\z/, number) do
      [_, real, imaginary] -> {:complex, complex_component(real), complex_component(imaginary)}
      nil -> {:complex, 0.0, complex_component(binary_part(number, 0, byte_size(number) - 1))}
    end
  end

  defp complex_component(number) do
    case FloatParser.parse(number) do
      {:ok, value} when is_float(value) -> value
      _ -> invalid("invalid complex component")
    end
  end

  defp integer(number) do
    {sign, number} =
      case number do
        "-" <> rest -> {-1, rest}
        "+" <> rest -> {1, rest}
        _ -> {1, number}
      end

    {base, digits} = integer_base(number)
    # Bound accumulation itself, not just the final result of a bignum parse.
    limit = if sign == -1, do: 9_223_372_036_854_775_808, else: 9_223_372_036_854_775_807

    value =
      for <<char <- digits>>, char != ?_, reduce: 0 do
        value ->
          digit = if char <= ?9, do: char - ?0, else: Bitwise.bor(char, 32) - ?a + 10
          value = value * base + digit
          if value > limit, do: invalid("template integer out of range")
          value
      end

    sign * value
  end

  defp integer_base(<<"0", char, rest::binary>>) when char in [?x, ?X], do: {16, rest}
  defp integer_base(<<"0", char, rest::binary>>) when char in [?b, ?B], do: {2, rest}
  defp integer_base(<<"0", char, rest::binary>>) when char in [?o, ?O], do: {8, rest}
  defp integer_base("0" <> rest), do: {8, rest}
  defp integer_base(number), do: {10, number}

  defp operand("."), do: {:root}

  defp operand(<<"$", _::binary>> = word) do
    case String.split(word, ".") do
      [name] -> {:variable, name}
      [name | fields] -> {:field, {:variable, name}, fields}
    end
  end

  defp operand(<<".", name::binary>>), do: {:field, {:root}, String.split(name, ".")}
  defp operand("true"), do: {:value, true}
  defp operand("false"), do: {:value, false}
  defp operand("nil"), do: {:value, nil}
  defp operand(name) when name in ["if", "with", "range", "break", "continue", "else", "end"], do: {:control, name}

  defp operand(name) do
    case String.split(name, ".") do
      [name] ->
        if Map.has_key?(@functions, name), do: {:function, name}, else: invalid("function #{name} not defined")

      [name | fields] ->
        case operand(name) do
          {:function, _} = function -> {:field, function, fields}
          _ -> invalid("unexpected field after literal")
        end
    end
  end

  defp character(<<"\\'", rest::binary>>), do: {?', rest}
  defp character(<<"\\\"", _rest::binary>>), do: invalid("invalid character escape")

  defp character(<<"\\", rest::binary>>) do
    {value, rest} = escape(rest)

    # Hex/octal byte escapes denote their numeric rune value, not a UTF-8
    # string. For example, '\\xFF' is the integer 255 rather than invalid UTF-8.
    case value do
      <<char>> -> {char, rest}
      <<char::utf8>> -> {char, rest}
    end
  end

  defp character(<<char::utf8, rest::binary>>) when char not in [?', 10], do: {char, rest}
  defp character(_), do: invalid("invalid character constant")

  defp quoted("", _quote, _acc), do: invalid("unterminated quoted string")
  defp quoted(<<char, rest::binary>>, char, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  defp quoted(<<13, rest::binary>>, ?`, acc), do: quoted(rest, ?`, acc)
  defp quoted(<<10, _::binary>>, ?", _acc), do: invalid("newline in quoted string")

  defp quoted(<<"\\", rest::binary>>, ?", acc) do
    {value, rest} = escape(rest)
    quoted(rest, ?", [value | acc])
  end

  defp quoted(<<char::utf8, rest::binary>>, quote, acc), do: quoted(rest, quote, [<<char::utf8>> | acc])
  defp quoted(_, _, _), do: invalid("invalid UTF-8 in quoted string")

  defp escape(<<char, rest::binary>>) when char in ~c"abfnrtv\\\"" do
    value = %{?a => 7, ?b => 8, ?f => 12, ?n => 10, ?r => 13, ?t => 9, ?v => 11, ?\\ => ?\\, ?" => ?"}
    {<<Map.fetch!(value, char)>>, rest}
  end

  defp escape(<<char, rest::binary>>) when char in ~c"xuU" do
    size = %{?x => 2, ?u => 4, ?U => 8}[char]
    {value, rest} = digits(rest, size, 16)

    cond do
      char == ?x -> {<<value>>, rest}
      value <= 0x10FFFF and value not in 0xD800..0xDFFF -> {<<value::utf8>>, rest}
      true -> invalid("invalid Unicode escape")
    end
  end

  defp escape(<<char, _::binary>> = source) when char in ?0..?7 do
    {value, rest} = digits(source, 3, 8)
    if value <= 255, do: {<<value>>, rest}, else: invalid("invalid octal escape")
  end

  defp escape(_), do: invalid("invalid string escape")

  defp digits(source, size, base) when byte_size(source) >= size do
    <<digits::binary-size(^size), rest::binary>> = source
    valid = if base == 8, do: ~r/\A[0-7]+\z/, else: ~r/\A[0-9a-fA-F]+\z/
    if not Regex.match?(valid, digits), do: invalid("invalid string escape")

    case Integer.parse(digits, base) do
      {value, ""} when value >= 0 -> {value, rest}
      _ -> invalid("invalid string escape")
    end
  end

  defp digits(_, _, _), do: invalid("incomplete string escape")

  defp pipeline(_tokens, depth, _variables) when depth > 64, do: invalid("template nesting limit")

  defp pipeline([{:variable, name}, binding | tokens], depth, variables) when binding in [:declare, :assign] do
    # Go adds the name before parsing its initializer, but establishes the
    # runtime binding only after evaluating it, including nested side effects.
    variables = MapSet.put(variables, name)
    {commands, rest, variables} = commands(tokens, depth, [], variables)
    {{:bind, binding, name, {:action, commands}}, rest, variables}
  end

  defp pipeline(tokens, depth, variables) do
    {commands, rest, variables} = commands(tokens, depth, [], variables)
    {{:action, commands}, rest, variables}
  end

  defp commands(tokens, depth, acc, variables) do
    {command, rest, variables} = command(tokens, depth, [], variables)

    if acc != [] and (match?([{:value, _} | _], command) or match?([{:root} | _], command)),
      do: invalid("non executable command in pipeline")

    case rest do
      [?| | rest] -> commands(rest, depth, [command | acc], variables)
      _ -> {Enum.reverse([command | acc]), rest, variables}
    end
  end

  defp command([?( | rest], depth, args, variables) do
    case pipeline(rest, depth + 1, variables) do
      {nested, [?), {:fields, fields} | tail], variables} ->
        command(tail, depth, [{:field, nested, fields} | args], variables)

      {nested, [?) | tail], variables} ->
        command(tail, depth, [nested | args], variables)

      _ ->
        invalid("unclosed parenthesis")
    end
  end

  defp command([{:control, _} | _], _depth, _args, _variables), do: invalid("unexpected template control action")

  defp command([token | rest], depth, args, variables) when is_tuple(token) do
    name =
      case token do
        {:variable, name} -> name
        {:field, {:variable, name}, _fields} -> name
        _ -> nil
      end

    if name != nil and not MapSet.member?(variables, name), do: invalid("undefined variable #{name}")
    command(rest, depth, [token | args], variables)
  end

  defp command(_rest, _depth, [], _variables), do: invalid("empty template command")
  defp command(rest, _depth, args, variables), do: {Enum.reverse(args), rest, variables}

  def render(template, labels, line, timestamp_ns) do
    # Bindings are template-local. A stack retains shadowed declarations and
    # lets assignments update the nearest binding without mutating labels.
    {parts, _state, :ok} = render_nodes(template, {[{"$", labels}], labels}, {line, timestamp_ns}, 0)
    {:ok, IO.iodata_to_binary(parts)}
  catch
    {:template_error, details} -> {:error, details}
  end

  defp render_nodes([], {variables, _dot}, _line, size), do: {[], {size, variables}, :ok}

  defp render_nodes([node | rest], {variables, dot}, line, size) do
    {part, {size, variables}, control} = render_node(node, {variables, dot}, line, size)

    if control == :ok do
      {parts, state, control} = render_nodes(rest, {variables, dot}, line, size)
      {[part | parts], state, control}
    else
      {[part], {size, variables}, control}
    end
  end

  defp render_node({kind, condition, yes, no}, {variables, dot}, line, size) when kind in [:if, :with] do
    {result, scoped} = value(condition, {variables, dot}, line)
    selected = if truthy?(result), do: yes, else: no
    inner_dot = if kind == :with and truthy?(result), do: result, else: dot
    {parts, {size, scoped}, control} = render_nodes(selected, {scoped, inner_dot}, line, size)
    # Keep updates to existing bindings, but pop this block's declarations.
    {parts, {size, Enum.drop(scoped, length(scoped) - length(variables))}, control}
  end

  defp render_node({:range, {binding, names, expression}, yes, no}, {variables, dot}, line, size) do
    {result, scoped} = value(expression, {variables, dot}, line)

    scoped =
      Enum.reduce(names, scoped, fn name, scoped ->
        {_result, scoped} = value({:bind, binding, name, {:value, result}}, {scoped, dot}, line)
        scoped
      end)

    values = range_values(result, length(names))
    {parts, {size, scoped}, control} = render_range(values, {binding, names, yes, no}, {scoped, dot}, line, size)
    {parts, {size, Enum.drop(scoped, length(scoped) - length(variables))}, control}
  end

  defp render_node(control, {variables, _dot}, _line, size) when control in [:break, :continue],
    do: {[], {size, variables}, control}

  defp render_node({:bind, _, _, _} = action, scope, line, size) do
    {_result, variables} = value(action, scope, line)
    {"", {size, variables}, :ok}
  end

  defp render_node(token, scope, line, size) do
    {result, variables} = value(token, scope, line)
    value = render_value(result)
    size = check_output_size(size + byte_size(value))
    {value, {size, variables}, :ok}
  end

  defp range_values(labels, _names) when is_map(labels), do: Enum.sort(labels)
  defp range_values({:object, values}, _names), do: Enum.sort(values)

  defp range_values({:array, view}, _names),
    do: view |> array_values() |> Stream.with_index() |> Stream.map(fn {value, index} -> {index, value} end)

  defp range_values(nil, _names), do: []

  defp range_values({:byte, count}, names),
    do: range_values(count, names) |> Stream.map(fn {key, value} -> {key, {:byte, value}} end)

  defp range_values(count, names) when is_integer(count) do
    if names > 1, do: invalid("integer range accepts at most one variable")
    if count > 0, do: Stream.map(0..(count - 1), &{nil, &1}), else: []
  end

  defp range_values(_value, _names), do: invalid("cannot range over this template value")

  defp render_range(values, {binding, names, yes, no}, {variables, dot}, line, size) do
    {parts, {size, variables}, empty?} =
      Enum.reduce_while(values, {[], {size, variables}, true}, fn {key, item}, {parts, {size, variables}, _empty?} ->
        charge_template_work(1)
        values = if length(names) == 2, do: [key, item], else: [item]
        bindings = Enum.zip(names, values)
        scoped = range_bindings(bindings, binding, variables)
        {part, {next_size, scoped}, control} = render_nodes(yes, {scoped, item}, line, size)
        scoped = Enum.drop(scoped, length(scoped) - length(variables))
        parts = if next_size == size, do: parts, else: [part | parts]
        state = {parts, {next_size, scoped}, false}
        if control == :break, do: {:halt, state}, else: {:cont, state}
      end)

    if empty?,
      do: render_nodes(no, {variables, dot}, line, size),
      else: {Enum.reverse(parts), {size, variables}, :ok}
  end

  defp range_bindings(bindings, :declare, variables), do: Enum.reverse(bindings, Enum.drop(variables, length(bindings)))

  defp range_bindings(bindings, _binding, variables),
    do:
      Enum.reduce(bindings, variables, fn {name, value}, variables ->
        List.keyreplace(variables, name, 0, {name, value})
      end)

  defp render_value(value) when is_float(value), do: Number.format(value, :general)
  defp render_value(value) when value in [:nan, :infinity, :negative_infinity], do: Number.format(value)
  defp render_value({:byte, value}), do: Integer.to_string(value)
  defp render_value(nil), do: "<no value>"

  defp render_value({:time, seconds, nanos}) do
    date = seconds |> DateTime.from_unix!(:second) |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

    fraction =
      if nanos == 0, do: "", else: "." <> String.trim_trailing(String.pad_leading(to_string(nanos), 9, "0"), "0")

    date <> fraction <> " +0000 UTC"
  end

  defp render_value({kind, _values} = value) when kind in [:object, :array] do
    {parts, _size} = composite_value(value, 0)
    IO.iodata_to_binary(parts)
  end

  defp render_value(labels) when is_map(labels) do
    # Root is map[string]string. Go prints its keys in lexical order; prove
    # the complete size before allocating the joined representation.
    {parts, _size} =
      Enum.map_reduce(Enum.sort(labels), 4, fn {name, value}, size ->
        size = check_output_size(size + byte_size(name) + byte_size(value) + 2)
        {[name, ":", value], size}
      end)

    IO.iodata_to_binary(["map[", Enum.intersperse(parts, " "), "]"])
  end

  defp render_value({:complex, real, imaginary}) do
    sign = if Number.sign(imaginary) < 0, do: "", else: "+"
    "(" <> Number.format(real, :general) <> sign <> Number.format(imaginary, :general) <> "i)"
  end

  defp render_value(value), do: to_string(value)

  defp composite_value({kind, values}, size) when kind in [:object, :array] do
    {open, values} =
      if kind == :object, do: {"map[", Enum.sort(values)}, else: {"[", array_values(values)}

    size = check_output_size(size + byte_size(open) + 1)

    {parts, size} =
      values
      |> Enum.with_index()
      |> Enum.map_reduce(size, fn {item, index}, size ->
        space = if index == 0, do: "", else: " "
        size = check_output_size(size + byte_size(space))

        {part, size} =
          if kind == :object do
            {key, value} = item
            size = check_output_size(size + byte_size(key) + 1)
            {part, size} = composite_value(value, size)
            {[key, ":", part], size}
          else
            composite_value(item, size)
          end

        {[space, part], size}
      end)

    {[open, parts, "]"], size}
  end

  defp composite_value(value, size) do
    text = if value == nil, do: "<nil>", else: render_value(value)
    {text, check_output_size(size + byte_size(text))}
  end

  defp array_values({_values, _offset, 0, _capacity}), do: []

  defp array_values({values, offset, size, _capacity}), do: Stream.map(0..(size - 1), &elem(values, offset + &1))

  defp value({:literal, text}, {variables, _dot}, _line), do: {text, variables}
  defp value({:root}, {variables, dot}, _line), do: {dot, variables}

  defp value({:variable, name}, {variables, _dot}, _line) do
    case List.keyfind(variables, name, 0) do
      {_, result} -> {result, variables}
      nil -> invalid("undefined variable #{name}")
    end
  end

  defp value({:field, _, _} = field, scope, line), do: field_value(field, scope, line, false)

  defp value({:value, {:float_literal, value}}, {variables, _dot}, _line), do: {value, variables}
  defp value({:value, value}, {variables, _dot}, _line), do: {value, variables}
  defp value({:function, name}, {variables, _dot}, line), do: {call(name, [], line), variables}

  defp value({:bind, binding, name, action}, scope, line) do
    {result, variables} = value(action, scope, line)

    variables =
      cond do
        binding == :declare -> [{name, result} | variables]
        List.keymember?(variables, name, 0) -> List.keyreplace(variables, name, 0, {name, result})
        true -> invalid("undefined variable #{name}")
      end

    {result, variables}
  end

  defp value({:action, commands}, {variables, dot}, line) do
    Enum.reduce(commands, {:first, variables}, fn command, {previous, variables} ->
      command_value(command, previous, {variables, dot}, line)
    end)
  end

  defp command_value([{:function, name} | args], previous, {variables, dot}, line) when name in ["and", "or"] do
    args = if previous == :first, do: args, else: args ++ [{:value, previous}]
    check_arity(name, length(args))

    Enum.reduce_while(args, {nil, variables}, fn arg, {_previous, variables} ->
      {result, variables} = value(arg, {variables, dot}, line)
      if truthy?(result) == (name == "or"), do: {:halt, {result, variables}}, else: {:cont, {result, variables}}
    end)
  end

  defp command_value([{:field, _, _} = head | args], previous, scope, line),
    do: field_value(head, scope, line, args != [] or previous != :first)

  defp command_value([head | args], previous, {variables, dot}, line) do
    integers = if match?({:function, _}, head), do: Map.get(@integer_arguments, elem(head, 1), []), else: []

    {args, variables} =
      args
      |> Enum.with_index()
      |> Enum.map_reduce(variables, fn {arg, index}, variables ->
        type =
          cond do
            index in integers -> :integer
            head == {:function, "round"} and index >= 2 -> :float
            true -> :value
          end

        argument_value(arg, type, {variables, dot}, line)
      end)

    args = if previous == :first, do: args, else: args ++ [previous]
    execute(head, args, {variables, dot}, line)
  end

  defp field_value({:field, base, fields}, scope, line, arguments?) do
    {result, variables} = value(base, scope, line)
    last = length(fields) - 1

    result =
      fields
      |> Enum.with_index()
      |> Enum.reduce(result, fn {field, index}, receiver ->
        fetch_field(receiver, field, index == last and arguments?)
      end)

    {if(result != :json_nil, do: result), variables}
  end

  # An invalid function result skips fields/arguments. A JSON map's nil
  # interface is different: more fields or field arguments must fail.
  defp fetch_field(nil, _field, _arguments?), do: nil
  defp fetch_field(_receiver, _field, true), do: invalid("template field is not a method but has arguments")
  defp fetch_field(labels, field, false) when is_map(labels), do: Map.get(labels, field, "")

  defp fetch_field({:object, values}, field, false) do
    case Map.get(values, field) do
      nil -> :json_nil
      value -> value
    end
  end

  defp fetch_field(_receiver, _field, _arguments?), do: invalid("cannot evaluate field on this template value")

  # Go's ideal constants can satisfy typed integer parameters directly. A
  # parenthesized or piped expression has already produced a typed float.
  defp argument_value({:value, {:complex, real, imaginary}}, type, labels, line)
       when imaginary == 0 and type in [:integer, :float],
       do: argument_value({:value, {:float_literal, real}}, type, labels, line)

  defp argument_value({:value, {:float_literal, value}}, :integer, {variables, _dot}, _line) do
    if value >= -9_223_372_036_854_775_808 and value < 9_223_372_036_854_775_808 and trunc(value) == value,
      do: {trunc(value), variables},
      else: invalid("expected integer constant")
  end

  defp argument_value({:value, value}, :float, {variables, _dot}, _line) when is_integer(value),
    do: {value / 1, variables}

  defp argument_value(arg, _type, labels, line), do: value(arg, labels, line)

  defp execute({:function, name}, args, {variables, _dot}, line), do: {call(name, args, line), variables}
  defp execute({:value, nil}, _args, _labels, _line), do: invalid("nil is not a command")
  defp execute(head, [], labels, line), do: value(head, labels, line)
  defp execute(_, _, _, _), do: invalid("template value is not a method but has arguments")

  defp call("__line__", args, {line, _timestamp_ns}) do
    check_arity("__line__", length(args))
    line
  end

  defp call("__timestamp__", args, {_line, timestamp_ns}) do
    check_arity("__timestamp__", length(args))
    time_value(timestamp_ns)
  end

  defp call(name, args, _entry) when name in ["unixToTime", "unixEpoch", "unixEpochMillis", "unixEpochNanos"] do
    check_arity(name, length(args))
    time_function(name, args)
  end

  defp call(name, args, _entry) do
    check_arity(name, length(args))

    cond do
      name == "default" ->
        default(args)

      name in [
        "not",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "len",
        "index",
        "slice",
        "print",
        "println",
        "html",
        "js",
        "urlquery"
      ] ->
        value_function(name, args)

      name in ["int", "add", "sub", "mul", "div", "mod", "min", "max"] ->
        arithmetic(name, Enum.map(args, &cast_integer/1))

      name in ["float64", "minf", "maxf", "floor", "ceil", "round", "addf", "subf", "mulf", "divf"] ->
        float_function(name, args)

      name in ["Replace", "repeat", "indent", "nindent", "alignLeft", "alignRight", "trunc", "substr"] ->
        integer_function(name, args)

      Enum.all?(args, &is_binary/1) ->
        string_function(name, args)

      true ->
        invalid("wrong type for #{name}: expected string")
    end
  end

  defp time_value(nanos) when is_integer(nanos),
    do: {:time, Integer.floor_div(nanos, 1_000_000_000), Integer.mod(nanos, 1_000_000_000)}

  defp time_value(_), do: invalid("missing entry timestamp")

  defp time_function("unixEpoch", [{:time, seconds, _nanos}]), do: Integer.to_string(seconds)

  defp time_function("unixEpochMillis", [{:time, seconds, nanos}]),
    do: Integer.to_string(wrap_integer(seconds * 1000 + div(nanos, 1_000_000)))

  defp time_function("unixEpochNanos", [{:time, seconds, nanos}]),
    do: Integer.to_string(wrap_integer(seconds * 1_000_000_000 + nanos))

  defp time_function("unixToTime", [text]) when is_binary(text) and byte_size(text) in [5, 10, 13, 16, 19] do
    # The pinned helper selects units by byte length, including signs/zeros.
    # Bound parsing first and retain Go's signed-int64 multiplication wrap.
    if not Regex.match?(~r/\A[+-]?[0-9]+\z/, text), do: invalid("invalid Unix time")
    value = String.to_integer(text)
    if value not in -9_223_372_036_854_775_808..9_223_372_036_854_775_807, do: invalid("Unix time out of range")

    case byte_size(text) do
      5 -> {:time, value * 86_400, 0}
      10 -> {:time, value, 0}
      13 -> time_value(wrap_integer(value * 1_000_000))
      16 -> time_value(wrap_integer(value * 1000))
      19 -> time_value(value)
    end
  end

  defp time_function(name, _args), do: invalid("invalid arguments for #{name}")

  defp check_arity(name, count) do
    case Map.fetch!(@functions, name) do
      {:min, min} when count >= min -> :ok
      ^count -> :ok
      expected -> invalid("wrong number of args for #{name}: want #{inspect(expected)} got #{count}")
    end
  end

  defguardp float_value?(value) when is_float(value) or value in [:nan, :infinity, :negative_infinity]

  defguardp ordered_pair?(left, right)
            when (is_integer(left) and is_integer(right)) or (float_value?(left) and float_value?(right)) or
                   (is_binary(left) and is_binary(right))

  defp truthy?(value) when is_number(value), do: value != 0
  defp truthy?({:byte, value}), do: value != 0
  defp truthy?(labels) when is_map(labels), do: map_size(labels) != 0
  defp truthy?({:object, values}), do: map_size(values) != 0
  defp truthy?({:array, {_values, _offset, size, _capacity}}), do: size != 0
  defp truthy?({:complex, real, imaginary}), do: real != 0 or imaginary != 0
  defp truthy?(value), do: value not in ["", false, nil]

  defp value_function("print", args), do: print_arguments(args, :print)
  defp value_function("println", args), do: print_arguments(args, :println)
  defp value_function("html", args), do: args |> print_arguments(:escape) |> html_escape()
  defp value_function("js", args), do: args |> print_arguments(:escape) |> js_escape()
  defp value_function("urlquery", args), do: string_function("urlencode", [print_arguments(args, :escape)])

  defp value_function("slice", [text | positions]) when is_binary(text) and length(positions) <= 2 do
    positions = Enum.map(positions, &slice_index/1)

    {start, stop} =
      case positions do
        [] -> {0, byte_size(text)}
        [start] -> {start, byte_size(text)}
        [start, stop] -> {start, stop}
      end

    if start < 0 or stop < start or stop > byte_size(text), do: invalid("slice bounds out of range")

    text |> binary_part(start, stop - start) |> utf8_result()
  end

  defp value_function("slice", [{:array, {values, offset, size, capacity}} | positions]) when length(positions) <= 3 do
    {start, stop, limit} =
      case Enum.map(positions, &slice_index/1) do
        [] -> {0, size, capacity}
        [start] -> {start, size, capacity}
        [start, stop] -> {start, stop, capacity}
        [start, stop, limit] -> {start, stop, limit}
      end

    if start < 0 or stop < start or limit < stop or limit > capacity, do: invalid("slice bounds out of range")

    # Keep a view, not a copied/truncated tuple: later slices may recover
    # decoded elements beyond this view's length, but never beyond its cap.
    {:array, {values, offset + start, stop - start, limit - start}}
  end

  defp value_function("index", [nil | _]), do: invalid("index of untyped nil")
  defp value_function("index", [item | indexes]), do: Enum.reduce(indexes, item, &index(&2, &1))
  defp value_function("not", [value]), do: not truthy?(value)
  defp value_function("len", [text]) when is_binary(text), do: byte_size(text)
  defp value_function("len", [labels]) when is_map(labels), do: map_size(labels)
  defp value_function("len", [{:object, values}]), do: map_size(values)
  defp value_function("len", [{:array, {_values, _offset, size, _capacity}}]), do: size
  defp value_function("eq", [first | rest]), do: Enum.any?(rest, &equal?(first, &1))
  defp value_function("ne", [left, right]), do: not equal?(left, right)

  defp value_function(name, [{:byte, left}, right]) when name in ["lt", "le", "gt", "ge"],
    do: value_function(name, [left, right])

  defp value_function(name, [left, {:byte, right}]) when name in ["lt", "le", "gt", "ge"],
    do: value_function(name, [left, right])

  defp value_function(name, [left, right]) when name in ["lt", "le", "gt", "ge"] and ordered_pair?(left, right) do
    case name do
      "lt" -> Number.less?(left, right)
      "le" -> Number.less?(left, right) or equal?(left, right)
      # text/template implements these as inverses, including for NaN.
      "gt" -> not (Number.less?(left, right) or equal?(left, right))
      "ge" -> not Number.less?(left, right)
    end
  end

  defp value_function(name, _args), do: invalid("wrong argument types for #{name}")

  # fmt.Sprint separates adjacent nonstrings; Sprintln separates all arguments
  # and appends a newline. Check the combined text before allocating its join.
  defp print_arguments(args, style) do
    newline? = style == :println
    ending = if newline?, do: "\n", else: ""

    {parts, _state} =
      Enum.map_reduce(Enum.with_index(args), {false, byte_size(ending)}, fn {arg, index}, {previous_string?, size} ->
        {text, string?} = printable_argument(arg, style)
        separator = if index > 0 and (newline? or not (string? or previous_string?)), do: " ", else: ""
        size = check_output_size(size + byte_size(separator) + byte_size(text))
        {[separator, text], {string?, size}}
      end)

    IO.iodata_to_binary([parts, ending])
  end

  # Escapers' evalArgs turns an invalid reflect.Value into a string before
  # fmt.Sprint. Ordinary print retains a nonstring nil, including its spacing.
  defp printable_argument(nil, :escape), do: {"<no value>", true}
  defp printable_argument(nil, _style), do: {"<nil>", false}
  defp printable_argument(value, _style), do: {render_value(value), is_binary(value)}

  defp html_escape(text) do
    size =
      for <<byte <- text>>, reduce: 0 do
        size ->
          escaped = Map.get(@html_escapes, <<byte>>)
          size + if(escaped, do: byte_size(escaped), else: 1)
      end

    check_output_size(size)
    html_escape_chunks(text, [])
  end

  # String.replace retains a list of every match. Bound that list per chunk,
  # not by the number of HTML-sensitive bytes in a full 16 MiB result.
  defp html_escape_chunks("", acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp html_escape_chunks(text, acc) do
    size = min(byte_size(text), 4096)
    <<chunk::binary-size(^size), rest::binary>> = text
    escaped = String.replace(chunk, Map.keys(@html_escapes), &Map.fetch!(@html_escapes, &1))
    html_escape_chunks(rest, [escaped | acc])
  end

  defp js_escape(text) do
    if Regex.match?(@js_special, text) do
      # Prove the complete escaped size before retaining expanded output.
      for <<char::utf8 <- text>>, reduce: 0 do
        size -> check_output_size(size + byte_size(js_character(char)))
      end

      js_escape_chunks(text, [])
    else
      text
    end
  end

  defp js_character(char) when char < 32, do: js_hex(char)
  defp js_character(char) when char < 128, do: Map.get(@js_escapes, char, <<char>>)

  defp js_character(char) do
    scalar = <<char::utf8>>
    if GoUnicode.printable?(scalar), do: scalar, else: js_hex(char)
  end

  # Go uses a minimum width of four, not JSON surrogate-pair escaping.
  defp js_hex(char), do: "\\u" <> String.pad_leading(Integer.to_string(char, 16), 4, "0")

  defp js_escape_chunks("", acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp js_escape_chunks(text, acc) do
    size = min(byte_size(text), 4096)
    size = if size < byte_size(text), do: scalar_boundary(text, size), else: size
    <<chunk::binary-size(^size), rest::binary>> = text
    escaped = for <<char::utf8 <- chunk>>, do: js_character(char)
    js_escape_chunks(rest, [IO.iodata_to_binary(escaped) | acc])
  end

  defp scalar_boundary(text, size) do
    if :binary.at(text, size) in 0x80..0xBF, do: scalar_boundary(text, size - 1), else: size
  end

  defp equal?(left, right) when is_nil(left) or is_nil(right), do: left == right
  defp equal?(left, right) when float_value?(left) and float_value?(right), do: Number.compare("==", left, right)
  defp equal?({:byte, left}, right), do: equal?(left, right)
  defp equal?(left, {:byte, right}), do: equal?(left, right)

  defp equal?({:complex, left_real, left_imaginary}, {:complex, right_real, right_imaginary}),
    do: left_real == right_real and left_imaginary == right_imaginary

  defp equal?({:time, _, _} = left, {:time, _, _} = right), do: left == right

  defp equal?(left, right) when ordered_pair?(left, right) or (is_boolean(left) and is_boolean(right)),
    do: left == right

  defp equal?(_, _), do: invalid("incompatible types for comparison")

  defp default([fallback, value]), do: if(truthy?(value), do: value, else: fallback)

  defp slice_index({:byte, value}), do: value
  defp slice_index(value) when is_integer(value), do: value
  defp slice_index(_value), do: invalid("invalid slice index type")

  defp index(item, {:byte, position}), do: index(item, position)
  defp index(labels, key) when is_map(labels) and is_binary(key), do: Map.get(labels, key, "")
  defp index({:object, values}, key) when is_binary(key), do: Map.get(values, key)

  defp index({:array, {values, offset, size, _capacity}}, position)
       when is_integer(position) and position >= 0 and position < size, do: elem(values, offset + position)

  # Keep uint8 distinct from int: comparisons/conversions accept both, but
  # typed int arguments require explicit conversion of a string byte.
  defp index(text, position)
       when is_binary(text) and is_integer(position) and position >= 0 and position < byte_size(text),
       do: {:byte, :binary.at(text, position)}

  defp index(_, _), do: invalid("invalid index type or out of range")

  defp cast_integer(value) when is_integer(value), do: value
  defp cast_integer({:byte, value}), do: value
  defp cast_integer(value) when is_map(value), do: 0
  defp cast_integer({kind, _values}) when kind in [:object, :array], do: 0
  defp cast_integer({:complex, _, _}), do: 0
  defp cast_integer({:time, _, _}), do: 0

  defp cast_integer(value) when is_float(value) do
    # Go leaves out-of-range float casts implementation-dependent. Preserve
    # portable in-range truncation, but never select a CPU-specific overflow.
    if value >= -9_223_372_036_854_775_808 and value < 9_223_372_036_854_775_808,
      do: trunc(value),
      else: invalid("float-to-integer out of range")
  end

  defp cast_integer(true), do: 1
  defp cast_integer(false), do: 0
  defp cast_integer(nil), do: 0

  defp cast_integer(value) when value in [:nan, :infinity, :negative_infinity],
    do: invalid("float-to-integer out of range")

  defp cast_integer(text) when is_binary(text) do
    # Sprig/cast truncates decimal strings before base-zero parsing, without
    # passing through float64. Invalid syntax and overflow both become zero.
    text =
      case Regex.run(~r/\A([+-]?[0-9]*)\.[0-9]*\z/, text) do
        [_, prefix] when prefix in ["", "+", "-"] -> "0"
        [_, prefix] -> prefix
        _ -> text
      end

    if Regex.match?(@integer_cast, text), do: integer(text), else: 0
  catch
    {:template_error, _details} -> 0
  end

  defp cast_float(value) when float_value?(value), do: value
  defp cast_float(value) when is_integer(value), do: value / 1
  defp cast_float({:byte, value}), do: value / 1
  defp cast_float(value) when is_map(value), do: 0.0
  defp cast_float({kind, _values}) when kind in [:object, :array], do: 0.0
  defp cast_float({:complex, _, _}), do: 0.0
  defp cast_float({:time, _, _}), do: 0.0
  defp cast_float(true), do: 1.0
  defp cast_float(false), do: 0.0
  defp cast_float(nil), do: 0.0

  defp cast_float(text) when is_binary(text) do
    case FloatParser.parse(text) do
      {:ok, value} -> value
      :error -> 0.0
    end
  end

  defp float_function("float64", [value]), do: cast_float(value)

  defp float_function(name, [first | rest]) when name in ["minf", "maxf"] do
    operation = if name == "minf", do: "min_of", else: "max_of"
    Enum.reduce(rest, cast_float(first), &Number.extremum(operation, &2, cast_float(&1)))
  end

  defp float_function(name, [value]) when name in ["floor", "ceil"], do: round_float(name, cast_float(value))

  # Sprig v3.3.0 numeric.go, copyright (C) 2013-2020 Masterminds, MIT.
  # License: test/fixtures/logs/loki-upstream/Sprig-LICENSE.
  defp float_function("round", [value, places | thresholds]) when is_integer(places) do
    if not Enum.all?(thresholds, &float_value?/1), do: invalid("round threshold must be float64")
    threshold = if thresholds == [], do: 0.5, else: hd(thresholds)
    power = decimal_power(places)
    value = cast_float(value)
    digit = Number.multiply(power, value)
    fraction = if is_number(digit), do: product_fraction(power, value, digit), else: :nan
    direction = if Number.compare(">=", fraction, threshold), do: "ceil", else: "floor"
    Number.divide(round_float(direction, digit), power)
  end

  # Sprig v3.3.0 converts each float64 to its shortest decimal, folds with
  # shopspring/decimal v1.4.0, then rounds to float64 only once per function.
  # MIT notices: test/fixtures/logs/loki-upstream/{Sprig,shopspring-decimal}-LICENSE.
  # A {coefficient, exponent} pair preserves that contract without a new
  # dependency. Finite input exponents/coefficients and the existing query
  # length/depth, worker heap and deadline bounds also bound intermediates.
  defp float_function(name, args) when name in ["addf", "subf", "mulf", "divf"] do
    [first | rest] = if name == "addf", do: [0 | args], else: args
    result = Enum.reduce(rest, to_decimal(first), &decimal_operation(name, &2, to_decimal(&1)))
    {coefficient, exponent} = result

    case FloatParser.parse("#{coefficient}e#{exponent}") do
      {:ok, value} -> value
      :error -> if coefficient < 0, do: :negative_infinity, else: :infinity
    end
  end

  defp float_function(name, _args), do: invalid("wrong argument types for #{name}")

  defp round_float("floor", value) when is_float(value), do: :math.floor(value)
  defp round_float("ceil", value) when is_float(value), do: :math.ceil(value)
  defp round_float(_direction, value), do: value

  # Go permits the multiply/subtract in inlined Modf to fuse. The pinned Loki
  # runtime does so; subtracting from an already rounded product changes half
  # ties. Compute the exact binary residual, then round once and copy its sign
  # from the rounded product, as Modf does. Float64 bounds keep integers small.
  defp product_fraction(left, right, product) do
    {left, left_exponent} = float_parts(left)
    {right, right_exponent} = float_parts(right)
    exponent = left_exponent + right_exponent
    mantissa = left * right

    {mantissa, exponent} =
      if exponent < 0,
        do: {mantissa - Bitwise.bsl(trunc(product), -exponent), exponent},
        else: {Bitwise.bsl(mantissa, exponent) - trunc(product), 0}

    sign = if Number.sign(product) < 0, do: "-", else: ""
    {:ok, fraction} = FloatParser.parse("#{sign}0x#{Integer.to_string(abs(mantissa), 16)}p#{exponent}")
    fraction
  end

  defp float_parts(value) do
    <<sign::1, exponent::11, mantissa::52>> = <<value::float-64>>

    {mantissa, exponent} =
      if exponent == 0, do: {mantissa, -1074}, else: {mantissa + 4_503_599_627_370_496, exponent - 1075}

    {if(sign == 0, do: mantissa, else: -mantissa), exponent}
  end

  defp decimal_power(places) when places > 308, do: :infinity
  defp decimal_power(places) when places < -323, do: 0.0

  defp decimal_power(places) do
    {fraction, exponent} = decimal_power(abs(places), 0.625, 4, 1.0, 0)
    {fraction, exponent} = if places < 0, do: {1 / fraction, -exponent}, else: {fraction, exponent}

    # Scale in the normal range first, so only the final multiplication rounds
    # a subnormal or reaches the upper exponent boundary.
    cond do
      exponent > 1023 -> fraction * :math.pow(2, exponent - 1023) * :math.pow(2, 1023)
      exponent < -1022 -> fraction * :math.pow(2, exponent + 1074) * :math.pow(2, -1074)
      true -> fraction * :math.pow(2, exponent)
    end
  end

  # Integer-exponent branch of Go 1.27.3 math.pow, Copyright 2009 The Go
  # Authors, BSD-3-Clause (test/fixtures/logs/loki-upstream/Go-LICENSE).
  # Keep its multiplication order, rather than substituting libm pow(10, n).
  defp decimal_power(0, _base, _exponent, fraction, total), do: {fraction, total}

  defp decimal_power(places, base, exponent, fraction, total) do
    {fraction, total} = if rem(places, 2) == 1, do: {fraction * base, total + exponent}, else: {fraction, total}
    base = base * base
    {base, exponent} = if base < 0.5, do: {base + base, exponent * 2 - 1}, else: {base, exponent * 2}
    decimal_power(div(places, 2), base, exponent, fraction, total)
  end

  defp to_decimal(value) do
    value = cast_float(value)
    if not is_float(value), do: invalid("cannot create a decimal from a nonfinite float")
    [mantissa | exponent] = value |> :erlang.float_to_binary([:short]) |> String.split("e")
    [whole, fraction] = String.split(mantissa, ".")
    exponent = if exponent == [], do: 0, else: String.to_integer(hd(exponent))
    {String.to_integer(whole <> fraction), exponent - byte_size(fraction)}
  end

  defp decimal_operation(name, {left, left_exp}, {right, right_exp}) when name in ["addf", "subf"] do
    exponent = min(left_exp, right_exp)
    left = left * Integer.pow(10, left_exp - exponent)
    right = right * Integer.pow(10, right_exp - exponent)
    {if(name == "addf", do: left + right, else: left - right), exponent}
  end

  defp decimal_operation("mulf", {left, left_exp}, {right, right_exp}), do: {left * right, left_exp + right_exp}
  defp decimal_operation("divf", _left, {0, _}), do: invalid("decimal division by zero")

  # shopspring DivRound rounds each quotient to 16 decimal places, with
  # halfway cases away from zero, before the next variadic fold step.
  defp decimal_operation("divf", {left, left_exp}, {right, right_exp}) do
    exponent = left_exp - right_exp + 16
    left = left * Integer.pow(10, max(exponent, 0))
    right = right * Integer.pow(10, max(-exponent, 0))
    quotient = div(left, right)
    direction = if left < 0 == right < 0, do: 1, else: -1
    correction = if 2 * abs(rem(left, right)) >= abs(right), do: direction, else: 0
    {quotient + correction, -16}
  end

  defp arithmetic("int", [value]), do: value
  defp arithmetic("add", values), do: Enum.reduce(values, 0, &wrap_integer(&1 + &2))
  defp arithmetic("sub", [left, right]), do: wrap_integer(left - right)
  defp arithmetic("mul", [first | rest]), do: Enum.reduce(rest, first, &wrap_integer(&1 * &2))
  defp arithmetic(name, [_, 0]) when name in ["div", "mod"], do: invalid("integer divide by zero")
  defp arithmetic("div", [left, right]), do: wrap_integer(div(left, right))
  defp arithmetic("mod", [left, right]), do: rem(left, right)
  defp arithmetic("min", values), do: Enum.min(values)
  defp arithmetic("max", values), do: Enum.max(values)

  # Truncate each operation, including every variadic fold step, to signed
  # int64 so repeated multiplication never accumulates unbounded bignums.
  defp wrap_integer(value) do
    <<wrapped::signed-64>> = <<value::signed-64>>
    wrapped
  end

  defp integer_function("Replace", [text, old, new, count])
       when is_binary(text) and is_binary(old) and is_binary(new) and is_integer(count),
       do: replace(text, old, new, count, [], 0)

  defp integer_function("repeat", [count, text]) when is_integer(count) and is_binary(text) do
    if count < 0, do: invalid("negative repeat count")
    check_output_size(count * byte_size(text))
    if text == "", do: "", else: :binary.copy(text, count)
  end

  defp integer_function(name, [count, text])
       when name in ["indent", "nindent"] and is_integer(count) and is_binary(text) do
    if count < 0, do: invalid("negative indentation count")
    prefix = if name == "nindent", do: "\n", else: ""

    newlines =
      for <<char <- text>>, reduce: 0 do
        total -> total + if(char == 10, do: 1, else: 0)
      end

    check_output_size(byte_size(prefix) + byte_size(text) + count * (newlines + 1))
    pad = :binary.copy(" ", count)
    body = if newlines == 0, do: text, else: :binary.replace(text, "\n", "\n" <> pad, [:global])
    IO.iodata_to_binary([prefix, pad, body])
  end

  defp integer_function(name, [count, text])
       when name in ["alignLeft", "alignRight"] and is_integer(count) and count < 0 and is_binary(text), do: text

  defp integer_function(name, [count, text])
       when name in ["alignLeft", "alignRight"] and is_integer(count) and is_binary(text) do
    length = for <<_char::utf8 <- text>>, reduce: 0, do: (total -> total + 1)

    if count >= length do
      check_output_size(byte_size(text) + count - length)
      pad = :binary.copy(" ", count - length)
      if name == "alignLeft", do: text <> pad, else: pad <> text
    else
      offset = rune_offset(text, if(name == "alignLeft", do: count, else: length - count), 0)

      if name == "alignLeft",
        do: binary_part(text, 0, offset),
        else: binary_part(text, offset, byte_size(text) - offset)
    end
  end

  # The public Loki function map installs Sprig's byte slices, not the
  # similarly named rune-based helpers in Loki's formatter source.
  defp integer_function("trunc", [count, text]) when is_integer(count) and is_binary(text) do
    size = byte_size(text)

    cond do
      count < 0 and size + count > 0 -> binary_part(text, size + count, -count)
      count >= 0 and count < size -> binary_part(text, 0, count)
      true -> text
    end
    |> utf8_result()
  end

  defp integer_function("substr", [start, stop, text])
       when is_integer(start) and is_integer(stop) and is_binary(text) do
    size = byte_size(text)

    {start, stop} =
      cond do
        start < 0 -> {0, stop}
        stop < 0 or stop > size -> {start, size}
        true -> {start, stop}
      end

    if start > stop or stop > size, do: invalid("slice bounds out of range")
    text |> binary_part(start, stop - start) |> utf8_result()
  end

  defp integer_function(name, _args), do: invalid("wrong argument types for #{name}")

  defp rune_offset(_text, 0, offset), do: offset

  defp rune_offset(<<_char::utf8, rest::binary>> = text, count, offset),
    do: rune_offset(rest, count - 1, offset + byte_size(text) - byte_size(rest))

  defp string_function(name, [text]) when name in ["upper", "ToUpper"], do: change_case(text, :upper, [])
  defp string_function(name, [text]) when name in ["lower", "ToLower"], do: change_case(text, :lower, [])
  defp string_function("bytes", [text]), do: quantity(Quantity.bytes_value(text), :bytes)

  defp string_function(name, [text]) when name in ["duration", "duration_seconds"],
    do: quantity(Quantity.duration_value(text), :duration)

  defp string_function("fromJson", [text]) do
    check_output_size(byte_size(text))
    # Charge the complete input before normalization/term expansion, including
    # malformed documents. Repeated decodes share loops' and regexes' budget.
    charge_template_work(byte_size(text))
    TemplateJSON.decode(text)
  end

  defp string_function("count", [pattern, text]) do
    case NIF.log_regex_count(pattern, text, remaining_template_work()) do
      {:ok, count} ->
        charge_template_work(count + 1)
        count

      {:error, :query_work_limit} ->
        throw({:logql_error, :query_work_limit})

      :error ->
        invalid("invalid count regular expression")
    end
  end

  defp string_function(name, [pattern, text, replacement]) when name in ["regexReplaceAll", "regexReplaceAllLiteral"] do
    literal? = name == "regexReplaceAllLiteral"

    case NIF.log_regex_replace(pattern, text, replacement, literal?, remaining_template_work(), @max_output_bytes) do
      {:ok, output, work} ->
        charge_template_work(work)
        output

      {:error, reason} ->
        throw({:logql_error, reason})

      :error ->
        invalid("invalid replacement regular expression")
    end
  end

  defp string_function(name, [text]) when name in ["trim", "TrimSpace"], do: Regex.replace(@space, text, "")
  defp string_function("trimAll", [cutset, text]), do: trim_set(text, cutset, :both)
  defp string_function("Trim", [text, cutset]), do: trim_set(text, cutset, :both)
  defp string_function("TrimLeft", [text, cutset]), do: trim_set(text, cutset, :left)
  defp string_function("TrimRight", [text, cutset]), do: trim_set(text, cutset, :right)
  defp string_function("replace", [old, new, text]), do: replace(text, old, new, -1, [], 0)
  defp string_function("title", [text]), do: title(text, true, [])

  defp string_function("b64enc", [text]) do
    check_output_size(div(byte_size(text) + 2, 3) * 4)
    Base.encode64(text)
  end

  defp string_function("b64dec", [text]) do
    # Loki pads before Go's decoder ignores CR/LF. Preserve original byte
    # offsets, including added padding, in ordinary corruption result strings.
    remainder = rem(byte_size(text), 4)
    padded = if remainder in [2, 3], do: text <> :binary.copy("=", 4 - remainder), else: text

    case base64_status(padded, 0, 0) do
      :ok ->
        encoded = :binary.replace(padded, ["\r", "\n"], "", [:global])

        padding =
          cond do
            String.ends_with?(encoded, "==") -> 2
            String.ends_with?(encoded, "=") -> 1
            true -> 0
          end

        check_output_size(div(byte_size(encoded), 4) * 3 - padding)
        encoded |> Base.decode64!() |> utf8_result()

      {:error, offset} ->
        "illegal base64 data at input byte #{offset}"
    end
  end

  defp string_function("urlencode", [text]) do
    size =
      for <<byte <- text>>, reduce: 0 do
        size -> size + if(byte == 32 or URI.char_unreserved?(byte), do: 1, else: 3)
      end

    check_output_size(size)
    URI.encode_www_form(text)
  end

  defp string_function("urldecode", [text]) do
    # URI.decode_www_form tolerates malformed escapes; Go QueryUnescape does not.
    if Regex.match?(~r/%(?![0-9a-fA-F]{2})/, text), do: invalid("invalid URL escape")
    text |> URI.decode_www_form() |> utf8_result()
  end

  defp string_function("trimPrefix", [prefix, text]), do: String.replace_prefix(text, prefix, "")
  defp string_function("trimSuffix", [suffix, text]), do: String.replace_suffix(text, suffix, "")
  defp string_function("TrimPrefix", [text, prefix]), do: String.replace_prefix(text, prefix, "")
  defp string_function("TrimSuffix", [text, suffix]), do: String.replace_suffix(text, suffix, "")
  defp string_function("contains", [part, text]), do: String.contains?(text, part)
  defp string_function("hasPrefix", [part, text]), do: String.starts_with?(text, part)
  defp string_function("hasSuffix", [part, text]), do: String.ends_with?(text, part)

  defp remaining_template_work, do: max(0, Evaluator.remaining(:work) - Process.get(:logql_template_work, 0))

  defp charge_template_work(count) do
    if count > remaining_template_work(), do: throw({:logql_error, :query_work_limit})

    if Process.get(:promql_budget) do
      Evaluator.charge(:work, count)
    else
      # Ordinary log workers do not initialize the metric budget. Keep one
      # request-local allowance across entries/actions, loops and regex helpers.
      work = Process.get(:logql_template_work, 0) + count
      Process.put(:logql_template_work, work)
    end
  end

  defp quantity({:ok, bytes}, :bytes), do: bytes / 1

  # time.Duration.Seconds splits before conversion, preserving the remainder
  # separately near int64 limits instead of rounding all nanoseconds first.
  defp quantity({:ok, ns}, :duration), do: div(ns, 1_000_000_000) + rem(ns, 1_000_000_000) / 1_000_000_000
  defp quantity({:error, details}, _type), do: invalid(details)

  defp utf8_result(value) do
    if not String.valid?(value), do: invalid("non-UTF-8 template results are unsupported")
    value
  end

  defp base64_status("", _offset, 0), do: :ok
  defp base64_status("", offset, digits), do: {:error, offset - digits}

  defp base64_status(<<char, rest::binary>>, offset, digits)
       when char in ?A..?Z or char in ?a..?z or char in ?0..?9 or char in [?+, ?/],
       do: base64_status(rest, offset + 1, rem(digits + 1, 4))

  defp base64_status(<<char, rest::binary>>, offset, digits) when char in [10, 13],
    do: base64_status(rest, offset + 1, digits)

  defp base64_status(<<"=", rest::binary>>, offset, 2) do
    case base64_skip_newlines(rest, offset + 1) do
      {"=" <> tail, next} -> base64_padding_end(tail, next + 1)
      {"", next} -> {:error, next}
      {_, next} -> {:error, next - 1}
    end
  end

  defp base64_status(<<"=", rest::binary>>, offset, 3), do: base64_padding_end(rest, offset + 1)
  defp base64_status(_text, offset, _digits), do: {:error, offset}

  defp base64_padding_end(text, offset) do
    case base64_skip_newlines(text, offset) do
      {"", _} -> :ok
      {_, next} -> {:error, next}
    end
  end

  defp base64_skip_newlines(<<char, rest::binary>>, offset) when char in [10, 13],
    do: base64_skip_newlines(rest, offset + 1)

  defp base64_skip_newlines(text, offset), do: {text, offset}

  defp trim_set(text, cutset, side) do
    set = MapSet.new(String.to_charlist(cutset))
    text = if side == :right, do: text, else: trim_start(text, set)
    if side == :left, do: text, else: binary_part(text, 0, trim_end(text, set, 0, 0))
  end

  defp trim_start(<<char::utf8, rest::binary>> = text, set) do
    if MapSet.member?(set, char), do: trim_start(rest, set), else: text
  end

  defp trim_start("", _set), do: ""

  defp trim_end("", _set, _offset, last), do: last

  defp trim_end(<<char::utf8, rest::binary>> = text, set, offset, last) do
    offset = offset + byte_size(text) - byte_size(rest)
    last = if MapSet.member?(set, char), do: last, else: offset
    trim_end(rest, set, offset, last)
  end

  # Empty matches split Go strings at rune boundaries, not grapheme boundaries.
  # Keep shared pieces until their exact total fits; never allocate amplification
  # and only then discover that a later trim would hide the oversized value.
  defp replace(text, _old, _new, 0, parts, size), do: finish_replacement(text, parts, size)

  defp replace(text, "", new, count, [], 0) do
    replace_empty(text, new, count - 1, [new], check_output_size(byte_size(new)))
  end

  defp replace(text, old, new, count, parts, size) do
    case :binary.match(text, old) do
      :nomatch ->
        finish_replacement(text, parts, size)

      {offset, length} ->
        <<prefix::binary-size(^offset), _::binary-size(^length), rest::binary>> = text
        size = check_output_size(size + offset + byte_size(new))
        replace(rest, old, new, count - 1, [[prefix, new] | parts], size)
    end
  end

  defp replace_empty(text, _new, 0, parts, size), do: finish_replacement(text, parts, size)
  defp replace_empty("", _new, _count, parts, size), do: finish_replacement("", parts, size)

  defp replace_empty(<<char::utf8, rest::binary>>, new, count, parts, size) do
    rune = <<char::utf8>>
    size = check_output_size(size + byte_size(rune) + byte_size(new))
    replace_empty(rest, new, count - 1, [new, rune | parts], size)
  end

  defp finish_replacement(text, parts, size) do
    check_output_size(size + byte_size(text))
    [text | parts] |> Enum.reverse() |> IO.iodata_to_binary()
  end

  # strings.Title preserves noninitial letters and uses its historical ASCII
  # punctuation/Unicode-space boundaries, not Unicode word segmentation.
  defp title("", _word_start?, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp title(<<char::utf8, rest::binary>>, word_start?, acc) do
    mapped = if word_start?, do: :unicode_util.get_case(char).title, else: char
    mapped = if is_integer(mapped), do: mapped, else: char

    separator? =
      if char <= 127,
        do: char not in ?a..?z and char not in ?A..?Z and char not in ?0..?9 and char != ?_,
        else: Regex.match?(@space, <<char::utf8>>)

    title(rest, separator?, [<<mapped::utf8>> | acc])
  end

  defp title(<<_byte, rest::binary>>, _word_start?, acc), do: title(rest, false, ["�" | acc])

  defp check_output_size(size) do
    if size > @max_output_bytes, do: throw({:logql_error, :query_result_limit})
    size
  end

  # Go maps one rune at a time, never expanding ß or ligatures. Greek
  # iota-subscript forms have a simple title mapping but a full upper list.
  defp change_case("", _direction, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()
  defp change_case(<<0x0130::utf8, rest::binary>>, :lower, acc), do: change_case(rest, :lower, ["i" | acc])

  defp change_case(<<char::utf8, rest::binary>>, direction, acc) do
    cases = :unicode_util.get_case(char)
    mapped = Map.fetch!(cases, direction)
    mapped = if is_list(mapped) and direction == :upper, do: cases.title, else: mapped
    mapped = if is_integer(mapped), do: mapped, else: char
    change_case(rest, direction, [<<mapped::utf8>> | acc])
  end

  defp change_case(<<_byte, rest::binary>>, direction, acc), do: change_case(rest, direction, ["�" | acc])

  defp invalid(details), do: throw({:template_error, details})
end
