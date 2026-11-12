defmodule Pulse.LogQL.Pipeline.Json do
  @moduledoc false

  # JSON field expressions are a separate grammar from LogQL string literals.
  # Inner quoted keys are not unescaped by the pinned field lexer.
  def expression(source) do
    with {:ok, key, rest} <- component(space(source), true), do: path(rest, [key])
  end

  defp path(source, keys) do
    case space(source) do
      "" -> {:ok, Enum.reverse(keys)}
      <<0, _::binary>> -> {:ok, Enum.reverse(keys)}
      <<".", rest::binary>> -> next_component(rest, keys, false)
      <<"[", _::binary>> = rest -> next_component(rest, keys, true)
      _ -> :error
    end
  end

  defp next_component(source, keys, bracket?) do
    with {:ok, key, rest} <- component(space(source), bracket?), do: path(rest, [key | keys])
  end

  defp component(<<"[", rest::binary>>, true) do
    with {:ok, key, rest} <- bracket_key(space(rest)), <<"]", rest::binary>> <- space(rest), do: {:ok, key, rest}
  end

  defp component(source, _) do
    case Regex.run(~r/\A[a-zA-Z_][a-zA-Z0-9_]*/, source) do
      [key] -> {:ok, key, binary_part(source, byte_size(key), byte_size(source) - byte_size(key))}
      _ -> :error
    end
  end

  defp bracket_key(<<"\"", rest::binary>>) do
    case :binary.match(rest, ["\"", "]", <<0>>]) do
      {size, 1} ->
        <<key::binary-size(^size), _delimiter, tail::binary>> = rest
        {:ok, key, tail}

      :nomatch ->
        :error
    end
  end

  defp bracket_key(source) do
    case Regex.run(~r/\A[0-9]+/, source) do
      [digits] when byte_size(digits) <= 19 ->
        index = String.to_integer(digits)

        if index <= 9_223_372_036_854_775_807,
          do: {:ok, index, binary_part(source, byte_size(digits), byte_size(source) - byte_size(digits))},
          else: :error

      _ ->
        :error
    end
  end

  defp space(<<char, rest::binary>>) when char in [32, 9, 10], do: space(rest)
  defp space(source), do: source

  # Seek only the requested path. Keep source slices for objects, arrays and
  # numbers: decoding/re-encoding would change whitespace, escapes and precision.
  # A complete selected value can precede a malformed/unclosed outer object.
  def fetch(line, path) do
    case seek(json_space(line), path, byte_size(line)) do
      {:ok, value, position} -> {:ok, value, position}
      _ -> :missing
    end
  end

  defp seek(source, [], size) do
    with {:ok, raw, _rest} <- value(source), do: {:ok, label_value(raw), size - byte_size(source)}
  end

  defp seek(<<"{", rest::binary>>, [key | _] = path, size) when is_binary(key), do: object(json_space(rest), path, size)

  defp seek(<<"[", rest::binary>>, [index | path], size) when is_integer(index),
    do: array(json_space(rest), index, path, size)

  defp seek(_, _, _), do: :missing

  defp object(<<"\"", _::binary>> = source, [key | path] = keys, size) do
    with {:ok, raw_key, rest} <- value(source),
         <<":", rest::binary>> <- json_space(rest) do
      rest = json_space(rest)
      found = if Pulse.JSON.decode(raw_key) == {:ok, key}, do: seek(rest, path, size), else: :missing

      case found do
        {:ok, _, _} -> found
        _ -> next_object(rest, keys, size)
      end
    else
      _ -> :missing
    end
  end

  defp object(_, _, _), do: :missing

  defp next_object(rest, keys, size) do
    with {:ok, _raw, tail} <- value(rest),
         <<",", tail::binary>> <- json_space(tail),
         do: object(json_space(tail), keys, size)
  end

  defp array(rest, 0, path, size), do: seek(rest, path, size)

  defp array(rest, index, path, size) do
    with {:ok, _raw, tail} <- value(rest),
         <<",", tail::binary>> <- json_space(tail),
         do: array(json_space(tail), index - 1, path, size)
  end

  defp value(<<"\"", _::binary>> = source) do
    with {:ok, tail} <- string_end(binary_part(source, 1, byte_size(source) - 1)),
         do: slice(source, tail)
  end

  defp value(<<char, rest::binary>> = source) when char in [?{, ?[] do
    close = if char == ?{, do: ?}, else: ?]
    with {:ok, tail} <- block_end(rest, [close]), do: slice(source, tail)
  end

  defp value(<<char, _::binary>> = source) when char in ~c"-0123456789tfn" do
    tail = scalar_end(source)
    slice(source, tail)
  end

  defp value(_), do: :missing

  defp slice(source, tail), do: {:ok, binary_part(source, 0, byte_size(source) - byte_size(tail)), tail}

  defp string_end(<<"\\", _, rest::binary>>), do: string_end(rest)
  defp string_end(<<"\"", rest::binary>>), do: {:ok, rest}
  defp string_end(<<_, rest::binary>>), do: string_end(rest)
  defp string_end(""), do: :missing

  defp block_end(<<"\"", rest::binary>>, stack) do
    with {:ok, tail} <- string_end(rest), do: block_end(tail, stack)
  end

  defp block_end(<<char, rest::binary>>, stack) when char in [?{, ?[] do
    close = if char == ?{, do: ?}, else: ?]
    block_end(rest, [close | stack])
  end

  defp block_end(<<char, rest::binary>>, [char]), do: {:ok, rest}
  defp block_end(<<char, rest::binary>>, [char | stack]), do: block_end(rest, stack)
  defp block_end(<<_, rest::binary>>, stack), do: block_end(rest, stack)
  defp block_end("", _), do: :missing

  defp scalar_end(<<char, _::binary>> = rest) when char in [32, 9, 10, 13, ?,, ?}, ?]], do: rest
  defp scalar_end(<<_, rest::binary>>), do: scalar_end(rest)
  defp scalar_end(""), do: ""

  defp json_space(<<char, rest::binary>>) when char in [32, 9, 10, 13], do: json_space(rest)
  defp json_space(source), do: source

  defp label_value("null"), do: ""

  defp label_value(<<"[", _::binary>> = raw) do
    # Arrays unescape as one string; objects stay verbatim. Protect bare
    # quotes/controls without doubling existing escapes before decoding once.
    escaped = Regex.replace(~r/\\.|"|[\x00-\x1f]/s, raw, &array_string_token/1)
    label_value("\"" <> escaped <> "\"")
  end

  defp label_value(<<"\"", _::binary>> = raw) do
    case Pulse.JSON.decode(raw) do
      {:ok, text} -> String.replace(text, "�", " ")
      _ -> ""
    end
  end

  defp label_value(raw), do: raw

  defp array_string_token(<<"\\", _::binary>> = escape), do: escape
  defp array_string_token("\""), do: "\\\""

  defp array_string_token(control) do
    encoded = Pulse.JSON.encode!(control)
    binary_part(encoded, 1, byte_size(encoded) - 2)
  end
end
