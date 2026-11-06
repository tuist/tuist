defmodule Pulse.LogQL.Pipeline.TemplateJSON do
  @moduledoc false

  alias Pulse.PromQL.FloatParser

  # Sprig fromJson uses encoding/json.Unmarshal into interface{}. Keep JSON
  # objects distinct from the formatter's map[string]string root. In particular,
  # their missing values are nil, not empty strings, and all numbers are floats.
  @max_bytes 16_777_216

  def decode(text) do
    decoders = [
      object_start: &start/1,
      array_start: &start/1,
      object_push: fn key, value, {depth, pairs} -> {depth, [{key, value} | pairs]} end,
      array_push: fn value, {depth, values} -> {depth, [value | values]} end,
      object_finish: fn {_depth, pairs}, parent -> {{:object, Map.new(Enum.reverse(pairs))}, parent} end,
      array_finish: &finish_array/2,
      integer: &number/1,
      float: &number/1
    ]

    case JSON.decode(normalize(text), {0, []}, decoders) do
      {value, _, ""} -> value
      _ -> nil
    end
  end

  defp finish_array({_depth, values}, parent) do
    values = values |> Enum.reverse() |> List.to_tuple()
    size = tuple_size(values)
    # Views retain decoded backing elements, not Go allocator spare slots.
    {{:array, {values, 0, size, size}}, parent}
  end

  # Apply the existing formatter nesting ceiling before expanding containers.
  # Exhaustion fails whole, rather than becoming fromJson's ordinary nil value.
  defp start({depth, _}) when depth >= 64, do: throw({:logql_error, :query_result_limit})
  defp start({depth, _}), do: {depth + 1, []}

  defp number(text) do
    case FloatParser.parse(text) do
      {:ok, value} -> value
      # Pinned Go 1.27.3 encoding/json retains a zero float at failed numeric
      # conversions, including inside otherwise decoded objects/arrays. Sprig
      # discards the error. Syntax errors still invalidate the entire document.
      :error -> 0.0
    end
  end

  defp normalize(text) do
    # OTP's JSON scanner otherwise loses integer negative zero, and rejects
    # lone UTF-16 surrogates. Preserve valid pairs and escaped backslashes;
    # leave every other escape/syntax check to JSON.decode.
    size = byte_size(text)
    check_size(size)

    text =
      if String.valid?(text) do
        text
      else
        check_size(utf8_size(text, 0))
        String.replace_invalid(text)
      end

    normalize_at(text, 0, 0, false, [], byte_size(text))
  end

  defp utf8_size("", size), do: size

  defp utf8_size(<<_char::utf8, rest::binary>> = source, size),
    do: utf8_size(rest, size + byte_size(source) - byte_size(rest))

  defp utf8_size(<<_byte, rest::binary>>, size), do: utf8_size(rest, size + 3)

  defp normalize_at(text, cursor, mark, quoted?, parts, size) do
    case :binary.match(text, ["\"", "\\", "-0"], scope: {cursor, byte_size(text) - cursor}) do
      :nomatch ->
        if parts == [],
          do: text,
          else: IO.iodata_to_binary(Enum.reverse([binary_part(text, mark, byte_size(text) - mark) | parts]))

      {pos, _} ->
        case :binary.at(text, pos) do
          ?" ->
            normalize_at(text, pos + 1, mark, not quoted?, parts, size)

          ?\\ when quoted? ->
            normalize_escape(text, pos, mark, parts, size)

          ?- when not quoted? ->
            normalize_zero(text, pos, mark, parts, size)

          _ ->
            normalize_at(text, pos + 1, mark, quoted?, parts, size)
        end
    end
  end

  defp normalize_escape(text, pos, mark, parts, size) do
    code = surrogate_at(text, pos)
    low = surrogate_at(text, pos + 6)

    cond do
      is_integer(code) and code in 0xD800..0xDBFF and is_integer(low) and low in 0xDC00..0xDFFF ->
        normalize_at(text, pos + 12, mark, true, parts, size)

      is_integer(code) and code in 0xD800..0xDFFF ->
        prefix = binary_part(text, mark, pos - mark)
        normalize_at(text, pos + 6, pos + 6, true, ["\\ufffd", prefix | parts], size)

      true ->
        normalize_at(text, min(pos + 2, byte_size(text)), mark, true, parts, size)
    end
  end

  defp normalize_zero(text, pos, mark, parts, size) do
    next = if pos + 2 < byte_size(text), do: :binary.at(text, pos + 2)

    if next in [nil, ?e, ?E, ?,, ?}, ?], 32, 9, 10, 13] do
      check_size(size + 2)
      prefix = binary_part(text, mark, pos + 2 - mark)
      normalize_at(text, pos + 2, pos + 2, false, [".0", prefix | parts], size + 2)
    else
      normalize_at(text, pos + 2, mark, false, parts, size)
    end
  end

  defp surrogate_at(text, pos) when pos + 6 <= byte_size(text) do
    case binary_part(text, pos, 6) do
      <<"\\u", hex::binary-size(4)>> ->
        case Integer.parse(hex, 16) do
          {code, ""} -> code
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp surrogate_at(_text, _pos), do: nil
  defp check_size(size) when size > @max_bytes, do: throw({:logql_error, :query_result_limit})
  defp check_size(_size), do: :ok
end
