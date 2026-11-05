defmodule Pulse.QueryRegex do
  @moduledoc false

  # Independent PCRE reference for the native Go-style Perl classes. Explicit
  # ranges also work inside existing classes; in particular Go \s excludes VT,
  # whereas PCRE \s includes it. Keep Unicode codepoints and strict end anchors.
  @ranges %{
    ?d => "0-9",
    ?D => "\\x00-\\x2f\\x3a-\\x{10ffff}",
    ?w => "A-Za-z0-9_",
    ?s => "\\t\\n\\f\\r ",
    ?S => "\\x00-\\x08\\x0b\\x0e-\\x1f\\x21-\\x{10ffff}"
  }

  @posix_ranges %{
    "alnum" => "0-9A-Za-z",
    "alpha" => "A-Za-z",
    "ascii" => "\\x00-\\x7f",
    "blank" => "\\t ",
    "cntrl" => "\\x00-\\x1f\\x7f",
    "digit" => "0-9",
    "graph" => "!-~",
    "lower" => "a-z",
    "print" => " -~",
    "punct" => "!-/:-@\\[-`{-~",
    "space" => "\\t\\n\\x0b\\f\\r ",
    "upper" => "A-Z",
    "word" => "0-9A-Z_a-z",
    "xdigit" => "0-9A-Fa-f"
  }

  def compile(pattern) do
    pattern |> translate(0, []) |> IO.iodata_to_binary() |> Regex.compile([:unicode, :dollar_endonly])
  end

  # An unfinished Go literal quote ends at the user's EOF, not after a
  # label-matching anchor or a flag scope supplied by the caller.
  def anchor(pattern), do: "(?s:\\A(?:" <> close_quote(pattern) <> ")\\z)"
  def non_dotall(pattern), do: "(?-s:" <> close_quote(pattern) <> ")"

  defp close_quote(pattern) do
    if :binary.match(pattern, "\\Q") != :nomatch and open_quote?(pattern, 0), do: pattern <> "\\E", else: pattern
  end

  defp open_quote?(<<>>, _depth), do: false

  defp open_quote?(<<"\\Q", rest::binary>>, 0) do
    case :binary.match(rest, "\\E") do
      :nomatch -> true
      {offset, 2} -> open_quote?(binary_part(rest, offset + 2, byte_size(rest) - offset - 2), 0)
    end
  end

  defp open_quote?(<<"\\", _char, rest::binary>>, depth), do: open_quote?(rest, depth)
  defp open_quote?(<<"[^]", rest::binary>>, 0), do: open_quote?(<<"[", rest::binary>>, 0)
  defp open_quote?(<<"[]", rest::binary>>, 0), do: open_quote?(<<"[", rest::binary>>, 0)

  defp open_quote?(<<"[", rest::binary>>, 0) do
    case take_class(rest, :member, []) do
      {_contents, tail} -> open_quote?(tail, 0)
      :unterminated -> false
    end
  end

  defp open_quote?(<<_char, rest::binary>>, depth), do: open_quote?(rest, depth)

  defp translate(<<>>, _depth, acc), do: Enum.reverse(acc)

  defp translate(<<"\\Q", rest::binary>>, 0, acc) do
    {literal, tail} =
      case :binary.match(rest, "\\E") do
        :nomatch -> {rest, ""}
        {offset, 2} -> {binary_part(rest, 0, offset), binary_part(rest, offset + 2, byte_size(rest) - offset - 2)}
      end

    translate(tail, 0, [Regex.escape(literal) | acc])
  end

  defp translate(<<"\\", first, second, rest::binary>>, depth, acc) when first in ?0..?7 and second in ?0..?7 do
    {value, tail} = octal(rest, (first - ?0) * 8 + second - ?0)
    translate(tail, depth, [["\\x{", Integer.to_string(value, 16), "}"] | acc])
  end

  defp translate(<<"\\0", rest::binary>>, depth, acc), do: translate(rest, depth, ["\\x{0}" | acc])

  defp translate(<<"\\", char, "{", rest::binary>>, depth, acc) when char in [?x, ?p, ?P] do
    case :binary.match(rest, "}") do
      {offset, 1} ->
        head = binary_part(rest, 0, offset + 1)
        tail = binary_part(rest, offset + 1, byte_size(rest) - offset - 1)
        translate(tail, depth, [["\\", <<char>>, "{", head] | acc])

      :nomatch ->
        Enum.reverse([["\\", <<char>>, "{", rest] | acc])
    end
  end

  defp translate(<<"{", rest::binary>>, 0, acc) do
    brace = if Regex.match?(~r/\A(?:0|[1-9][0-9]*)(?:,(?:0|[1-9][0-9]*)?)?\}/, rest), do: "{", else: "\\{"
    translate(rest, 0, [brace | acc])
  end

  defp translate(<<"[^]", rest::binary>>, 0, acc), do: translate(<<"[^\\]", rest::binary>>, 0, acc)
  defp translate(<<"[]", rest::binary>>, 0, acc), do: translate(<<"[\\]", rest::binary>>, 0, acc)

  defp translate(<<"[", rest::binary>>, 0, acc) do
    case take_class(rest, :member, []) do
      {contents, tail} -> translate(tail, 0, [class(contents) | acc])
      :unterminated -> Enum.reverse([["[", rest] | acc])
    end
  end

  # PCRE's named ASCII classes do not apply Go's Unicode simple case folding.
  # Explicit ranges do; complement classes are lifted out before this pass.
  defp translate(<<"[:", rest::binary>>, depth, acc) when depth > 0 do
    with [name, tail] <- :binary.split(rest, ":]"),
         {:ok, range} <- Map.fetch(@posix_ranges, name) do
      translate(tail, depth, [range | acc])
    else
      _ -> translate(rest, depth + 1, ["[:" | acc])
    end
  end

  defp translate(<<"\\", char, rest::binary>>, depth, acc) do
    replacement =
      case Map.fetch(@ranges, char) do
        {:ok, range} -> if depth > 0, do: range, else: ["[", range, "]"]
        :error when char == ?W -> "[^A-Za-z0-9_]"
        :error when char == ?v -> "\\x0b"
        :error -> ["\\", <<char>>]
      end

    translate(rest, depth, [replacement | acc])
  end

  defp translate(<<char, rest::binary>>, depth, acc) do
    next =
      case char do
        ?[ -> depth + 1
        ?] -> max(0, depth - 1)
        _ -> depth
      end

    translate(rest, next, [<<char>> | acc])
  end

  defp octal(<<digit, rest::binary>>, value) when digit in ?0..?7, do: {value * 8 + digit - ?0, rest}
  defp octal(rest, value), do: {value, rest}

  # A positive complement range would incorrectly re-admit Unicode folds of
  # ASCII letters under (?i). Lift complements out as negated classes instead.
  # Lookahead here is only an independent reference implementation detail.
  defp class(contents) do
    {negative?, body} =
      case contents do
        <<"^", rest::binary>> -> {true, rest}
        _ -> {false, contents}
      end

    {body, complements} = strip_complements(body, [], [])

    if complements == [] do
      ["[", translate(contents, 1, []), "]"]
    else
      # Removing a leading complement must not turn a following literal ^ into a
      # new class-negation marker.
      literal =
        case body do
          <<"^", tail::binary>> -> <<"\\^", tail::binary>>
          _ -> body
        end

      other = if literal == "", do: [], else: ["|[", translate(literal, 1, []), "]"]
      union = [Enum.intersperse(complements, "|"), other]
      if negative?, do: ["(?:(?!(?:", union, "))(?s:.))"], else: ["(?:", union, ")"]
    end
  end

  defp strip_complements(<<>>, acc, complements), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), complements}

  defp strip_complements(<<"\\W", rest::binary>>, acc, complements),
    do: strip_complement(rest, acc, ["[^A-Za-z0-9_]" | complements])

  defp strip_complements(<<"[:^", rest::binary>>, acc, complements) do
    with [name, tail] <- :binary.split(rest, ":]"),
         {:ok, range} <- Map.fetch(@posix_ranges, name) do
      strip_complement(tail, acc, [["[^", range, "]"] | complements])
    else
      _ -> strip_complements(rest, ["[:^" | acc], complements)
    end
  end

  defp strip_complements(<<"\\", c, rest::binary>>, acc, complements),
    do: strip_complements(rest, [["\\", <<c>>] | acc], complements)

  defp strip_complements(<<c, rest::binary>>, acc, complements), do: strip_complements(rest, [<<c>> | acc], complements)

  # Do not join two literal neighbours into a new range when removing a class.
  defp strip_complement(<<"-", rest::binary>>, acc, complements),
    do: strip_complements(rest, ["\\-" | acc], complements)

  defp strip_complement(rest, acc, complements), do: strip_complements(rest, acc, complements)

  # Go ranges consume one scalar at either end. Complete class escapes are
  # members, not scalar endpoints, and a later hyphen starts a new member.
  defp take_class(<<>>, _state, _acc), do: :unterminated
  defp take_class(<<"]", rest::binary>>, _state, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  defp take_class(<<"^", rest::binary>>, :member, []), do: take_class(rest, :member, ["^"])

  defp take_class(<<"-", next, _::binary>> = input, :scalar, acc) when next != ?],
    do: take_class(binary_part(input, 1, byte_size(input) - 1), :range_end, ["-" | acc])

  defp take_class(<<"[:", rest::binary>>, state, acc) when state != :range_end do
    case :binary.match(rest, ":]") do
      {offset, 2} ->
        head = binary_part(rest, 0, offset + 2)
        tail = binary_part(rest, offset + 2, byte_size(rest) - offset - 2)
        take_class(tail, :member, [["[:", head] | acc])

      :nomatch ->
        take_class(rest, :scalar, ["\\[\\:" | acc])
    end
  end

  defp take_class(<<"\\", char, "{", rest::binary>>, state, acc) when char in [?x, ?p, ?P] do
    case :binary.match(rest, "}") do
      {offset, 1} ->
        head = binary_part(rest, 0, offset + 1)
        tail = binary_part(rest, offset + 1, byte_size(rest) - offset - 1)
        next = if char != ?x or state == :range_end, do: :member, else: :scalar
        take_class(tail, next, [["\\", <<char>>, "{", head] | acc])

      :nomatch ->
        :unterminated
    end
  end

  defp take_class(<<"\\x", first, second, rest::binary>>, state, acc),
    do: take_class(rest, if(state == :range_end, do: :member, else: :scalar), [["\\x", <<first, second>>] | acc])

  defp take_class(<<"\\", first, second, rest::binary>>, state, acc) when first in ?0..?7 and second in ?0..?7 do
    {value, tail} = octal(rest, (first - ?0) * 8 + second - ?0)
    next = if state == :range_end, do: :member, else: :scalar
    take_class(tail, next, [["\\x{", Integer.to_string(value, 16), "}"] | acc])
  end

  defp take_class(<<"\\", char, property::utf8, rest::binary>>, _state, acc) when char in [?p, ?P],
    do: take_class(rest, :member, [["\\", <<char, property::utf8>>] | acc])

  defp take_class(<<"\\", char::utf8, rest::binary>>, state, acc) do
    next = if char in ~c"dDsSwW" or state == :range_end, do: :member, else: :scalar
    take_class(rest, next, [["\\", <<char::utf8>>] | acc])
  end

  defp take_class(<<char::utf8, rest::binary>>, state, acc) do
    literal = if char in ~c"[-:", do: ["\\", <<char>>], else: <<char::utf8>>
    take_class(rest, if(state == :range_end, do: :member, else: :scalar), [literal | acc])
  end
end
