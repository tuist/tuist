defmodule Pulse.LogQL.Pipeline.Logfmt do
  @moduledoc """
  Logfmt field decoding for query pipelines and field discovery.

  Non-strict decoding discards malformed pairs and resumes at the next token.
  Strict decoding stops at the first error, retaining earlier valid pairs.
  Positions are one-based byte offsets, including end-of-input errors.
  """

  @escapes %{?" => ?", ?' => ?', ?/ => ?/, ?\\ => ?\\, ?b => 8, ?f => 12, ?n => 10, ?r => 13, ?t => 9}

  @spec parse(binary(), boolean()) :: [{binary(), binary()}]
  def parse(line, keep_empty? \\ false) when is_binary(line) do
    {pairs, _error} = decode(line, false)
    if keep_empty?, do: pairs, else: Enum.reject(pairs, &(elem(&1, 1) == ""))
  end

  @doc false
  @spec decode(binary(), boolean(), :all | :explicit) :: {[{binary(), binary()}], binary() | nil}
  def decode(line, strict?, mode \\ :all), do: scan(line, 0, [], strict?, mode)

  @doc false
  @spec expression(binary()) :: {:ok, binary()} | :error
  def expression(source) do
    case expression_tokens(source, []) do
      {:ok, [first | extra]} ->
        # Loki formats its parsed path with Go's fmt.Sprintf("%v", path...).
        # Additional quoted components are formatting extras, not JSON paths.
        suffix = if extra == [], do: "", else: "%!(EXTRA " <> Enum.map_join(extra, ", ", &("string=" <> &1)) <> ")"
        {:ok, first <> suffix}

      _ ->
        :error
    end
  end

  defp expression_tokens(<<char, rest::binary>>, tokens) when char in [32, 9, 10], do: expression_tokens(rest, tokens)

  defp expression_tokens(<<0, _::binary>>, tokens), do: {:ok, Enum.reverse(tokens)}
  defp expression_tokens("", tokens), do: {:ok, Enum.reverse(tokens)}

  defp expression_tokens(<<?", rest::binary>>, tokens) do
    # The pinned field lexer does not unescape inner strings, and also ends
    # them at ']', NUL or EOF. The outer LogQL literal is decoded separately.
    case :binary.match(rest, ["\"", "]", <<0>>]) do
      {size, 1} ->
        <<value::binary-size(^size), _delimiter, tail::binary>> = rest
        expression_tokens(tail, [value | tokens])

      :nomatch ->
        {:ok, Enum.reverse([rest | tokens])}
    end
  end

  defp expression_tokens(source, []) do
    case Regex.run(~r/\A[a-zA-Z_][a-zA-Z0-9_]*/, source) do
      [key] -> expression_tokens(binary_part(source, byte_size(key), byte_size(source) - byte_size(key)), [key])
      _ -> :error
    end
  end

  defp expression_tokens(_, _), do: :error

  defp scan(line, pos, pairs, strict?, mode) do
    pos = skip_ws(line, pos)

    if pos == byte_size(line) do
      {Enum.reverse(pairs), nil}
    else
      case pair(line, pos) do
        {:ok, key, value, next} -> scan(line, next, [{key, clean(value, mode)} | pairs], strict?, mode)
        {:error, details, _next} when strict? -> {Enum.reverse(pairs), details}
        {:error, _details, next} -> scan(line, next, pairs, strict?, mode)
      end
    end
  end

  defp skip_ws(line, pos) do
    if pos < byte_size(line) and :binary.at(line, pos) <= 32, do: skip_ws(line, pos + 1), else: pos
  end

  defp pair(line, start) do
    pos = token_end(line, start, [?=, ?"])
    key = binary_part(line, start, pos - start)
    char = if pos < byte_size(line), do: :binary.at(line, pos)

    cond do
      char == ?" -> error(line, pos, ~s/unexpected '"'/)
      key == "" -> error(line, pos, "unexpected '='")
      not String.valid?(key) or String.contains?(key, "�") -> error(line, pos, "invalid key")
      char == ?= -> value(line, pos + 1, key)
      true -> {:ok, key, "", pos}
    end
  end

  defp token_end(line, pos, stops) do
    if pos == byte_size(line) or :binary.at(line, pos) <= 32 or :binary.at(line, pos) in stops,
      do: pos,
      else: token_end(line, pos + 1, stops)
  end

  defp value(line, pos, key) do
    cond do
      pos == byte_size(line) or :binary.at(line, pos) <= 32 ->
        {:ok, key, "", pos}

      :binary.at(line, pos) == ?" ->
        quoted(line, pos + 1, pos + 1, key)

      true ->
        finish = token_end(line, pos, [?=, ?"])

        if finish < byte_size(line) and :binary.at(line, finish) in [?=, ?"] do
          char = <<:binary.at(line, finish)>>
          error(line, finish, "unexpected '#{char}'")
        else
          {:ok, key, binary_part(line, pos, finish - pos), finish}
        end
    end
  end

  defp error(line, pos, message) do
    {:error, diagnostic(pos, message), token_end(line, pos, [])}
  end

  defp diagnostic(pos, message), do: "logfmt syntax error at pos #{pos + 1} : #{message}"

  defp quoted(line, pos, start, key) do
    cond do
      pos >= byte_size(line) ->
        {:error, diagnostic(byte_size(line), "unterminated quoted value"), byte_size(line)}

      :binary.at(line, pos) == ?" ->
        case unquote(binary_part(line, start, pos - start), []) do
          {:ok, value} -> {:ok, key, value, pos + 1}
          :error -> {:error, diagnostic(pos + 1, "invalid quoted value"), pos + 1}
        end

      :binary.at(line, pos) == ?\\ ->
        quoted(line, pos + 2, start, key)

      true ->
        quoted(line, pos + 1, start, key)
    end
  end

  defp unquote("", acc), do: {:ok, IO.iodata_to_binary(Enum.reverse(acc))}

  defp unquote(<<"\\u", hex::binary-size(4), rest::binary>>, acc) do
    if Regex.match?(~r/\A[0-9a-fA-F]{4}\z/, hex) do
      unicode(String.to_integer(hex, 16), rest, acc)
    else
      :error
    end
  end

  defp unquote(<<?\\, char, rest::binary>>, acc) do
    case Map.fetch(@escapes, char) do
      {:ok, decoded} -> unquote(rest, [<<decoded>> | acc])
      :error -> :error
    end
  end

  defp unquote(<<?\\>>, _acc), do: :error
  defp unquote(<<char, rest::binary>>, acc), do: unquote(rest, [<<char>> | acc])

  defp unicode(high, <<"\\u", low::binary-size(4), rest::binary>> = remaining, acc) when high in 0xD800..0xDBFF do
    case Integer.parse(low, 16) do
      {low, ""} when low in 0xDC00..0xDFFF ->
        codepoint = 0x10000 + (high - 0xD800) * 1024 + low - 0xDC00
        unquote(rest, [<<codepoint::utf8>> | acc])

      _ ->
        unquote(remaining, ["�" | acc])
    end
  end

  defp unicode(value, rest, acc) when value in 0xD800..0xDFFF, do: unquote(rest, ["�" | acc])
  defp unicode(value, rest, acc), do: unquote(rest, [<<value::utf8>> | acc])

  defp clean(value, :explicit) do
    if String.valid?(value) and not String.contains?(value, "�"), do: value, else: ""
  end

  defp clean(value, :all), do: value |> String.replace_invalid(" ") |> String.replace("�", " ")
end
