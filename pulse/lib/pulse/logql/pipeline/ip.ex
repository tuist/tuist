defmodule Pulse.LogQL.Pipeline.IP do
  @moduledoc false
  import Bitwise

  # Keep address families distinct, including IPv4-mapped IPv6. A compiled
  # pattern is a closed integer interval plus the single-address zone, if any.
  @type matcher :: {32 | 128, non_neg_integer(), non_neg_integer(), binary() | nil}

  @spec compile(binary()) :: {:ok, matcher()} | {:error, term()}
  def compile(pattern) do
    case address(pattern) do
      {:ok, {bits, value, zone}} -> {:ok, {bits, value, value, zone}}
      :error -> compile_interval(pattern)
    end
  end

  defp compile_interval(pattern) do
    case :binary.split(pattern, "/") do
      [ip, prefix] ->
        case prefix(ip, prefix, pattern) do
          {:ok, _} = result -> result
          _ -> range(pattern)
        end

      [_] ->
        range(pattern)
    end
  end

  defp prefix(ip, prefix, pattern) do
    with {:ok, {bits, value, nil}} <- address(ip),
         true <- byte_size(prefix) in 1..3,
         {length, ""} <- Integer.parse(prefix),
         true <- prefix == Integer.to_string(length) and length in 0..bits do
      size = 1 <<< (bits - length)
      first = div(value, size) * size
      {:ok, {bits, first, first + size - 1, nil}}
    else
      _ -> {:error, {:invalid_ip_pattern, pattern}}
    end
  end

  defp range(pattern) do
    with [from, to] <- :binary.split(pattern, "-"),
         {:ok, {bits, first, _}} <- address(from),
         {:ok, {^bits, last, _}} <- address(to),
         true <- first <= last do
      {:ok, {bits, first, last, nil}}
    else
      _ -> {:error, {:invalid_ip_pattern, pattern}}
    end
  end

  defp address(text) do
    {ip, zone} =
      case :binary.split(text, "%") do
        [ip] -> {ip, nil}
        [ip, zone] -> {ip, zone}
      end

    with true <- byte_size(ip) in 2..45 and zone != "",
         {:ok, tuple} <- :inet.parse_strict_address(:binary.bin_to_list(ip)),
         bits = if(tuple_size(tuple) == 4, do: 32, else: 128),
         true <- is_nil(zone) or bits == 128 do
      width = if bits == 32, do: 8, else: 16
      value = tuple |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> (acc <<< width) + part end)
      {:ok, {bits, value, zone}}
    else
      _ -> :error
    end
  end

  @spec matches?(matcher(), binary()) :: boolean()
  # Candidate extraction excludes zones, so a zoned single-address pattern
  # cannot equal a candidate. Range patterns strip zones, as netipx does.
  def matches?({_, _, _, zone}, _) when not is_nil(zone), do: false
  def matches?(matcher, text), do: scan(text, matcher)

  defp scan(<<>>, _), do: false

  defp scan(text, matcher) do
    case candidate_family(text) do
      nil ->
        <<_, rest::binary>> = text
        scan(rest, matcher)

      family ->
        {length, rest} = span(text, family, 0)

        # Loki resumes after the maximal candidate and one delimiter, not
        # at every suffix of an invalid address or a port-bearing IPv6 token.
        rest =
          case rest do
            <<_, tail::binary>> -> tail
            <<>> -> <<>>
          end

        candidate_matches?(text, length, matcher) or scan(rest, matcher)
    end
  end

  defp candidate_matches?(text, length, {bits, first, last, nil}) when length <= 45 do
    case address(binary_part(text, 0, length)) do
      {:ok, {^bits, value, nil}} -> value >= first and value <= last
      _ -> false
    end
  end

  defp candidate_matches?(_, _, _), do: false

  defguardp hex?(byte) when byte in ?0..?9 or byte in ?a..?f or byte in ?A..?F

  # IPv4 hints take precedence. The following IPv6 hints intentionally do not
  # recognize a bare ::; this is Loki's candidate grammar, not a generic lexer.
  defp candidate_family(<<a, b, c, d, _::binary>>) when a in ?0..?9 and (b == ?. or c == ?. or d == ?.), do: :v4

  defp candidate_family(<<?:, ?:, a, _::binary>>) when hex?(a), do: :v6
  defp candidate_family(<<a, ?:, _::binary>>) when hex?(a), do: :v6
  defp candidate_family(<<a, b, ?:, _::binary>>) when hex?(a) and hex?(b), do: :v6
  defp candidate_family(<<a, b, c, ?:, _::binary>>) when hex?(a) and hex?(b) and hex?(c), do: :v6
  defp candidate_family(<<a, b, c, d, ?:, _::binary>>) when hex?(a) and hex?(b) and hex?(c) and hex?(d), do: :v6
  defp candidate_family(_), do: nil

  defp span(<<byte, rest::binary>>, :v4, length) when byte in ?0..?9 or byte == ?., do: span(rest, :v4, length + 1)

  defp span(<<byte, rest::binary>>, :v6, length) when hex?(byte) or byte in [?:, ?.], do: span(rest, :v6, length + 1)

  defp span(rest, _, length), do: {length, rest}
end
