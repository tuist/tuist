defmodule Pulse.PromQL.LabelHash do
  @moduledoc false
  import Bitwise

  @mask 0xFFFFFFFFFFFFFFFF
  @p1 11_400_714_785_074_694_791
  @p2 14_029_467_366_897_019_727
  @p3 1_609_587_929_392_839_161
  @p4 9_650_029_242_287_828_579
  @p5 2_870_177_450_012_600_261

  # The pinned Prometheus/Mimir default stringlabels representation uses
  # length-prefixed strings, not the separator-based StableHash used by storage.
  # XXH64 is implemented here in Elixir; no native ABI is required for queries.
  def hash(labels) do
    bytes = labels |> Enum.sort() |> Enum.map(fn {k, v} -> [string(k), string(v)] end) |> IO.iodata_to_binary()

    {hash, tail} =
      if byte_size(bytes) < 32 do
        {@p5, bytes}
      else
        {lanes, tail} = blocks(bytes, {uint(@p1 + @p2), @p2, 0, uint(-@p1)})
        {a, b, c, d} = lanes
        hash = uint(rotate(a, 1) + rotate(b, 7) + rotate(c, 12) + rotate(d, 18))

        hash =
          Enum.reduce(Tuple.to_list(lanes), hash, fn lane, hash ->
            uint(bxor(hash, round_lane(0, lane)) * @p1 + @p4)
          end)

        {hash, tail}
      end

    hash = tail(tail, uint(hash + byte_size(bytes)))
    hash = uint(bxor(hash, hash >>> 33) * @p2)
    hash = uint(bxor(hash, hash >>> 29) * @p3)
    bxor(hash, hash >>> 32)
  end

  defp string(value) when byte_size(value) < 255, do: [<<byte_size(value)>>, value]
  defp string(value) when byte_size(value) < 16_777_216, do: [<<255, byte_size(value)::little-24>>, value]
  defp string(_), do: throw({:promql_error, :query_work_limit})

  defp blocks(<<a::little-64, b::little-64, c::little-64, d::little-64, rest::binary>>, {v1, v2, v3, v4}) do
    blocks(rest, {round_lane(v1, a), round_lane(v2, b), round_lane(v3, c), round_lane(v4, d)})
  end

  defp blocks(rest, lanes), do: {lanes, rest}
  defp round_lane(acc, word), do: uint(rotate(uint(acc + word * @p2), 31) * @p1)

  defp tail(<<word::little-64, rest::binary>>, hash),
    do: tail(rest, uint(rotate(bxor(hash, round_lane(0, word)), 27) * @p1 + @p4))

  defp tail(<<word::little-32, rest::binary>>, hash),
    do: tail(rest, uint(rotate(bxor(hash, uint(word * @p1)), 23) * @p2 + @p3))

  defp tail(<<byte, rest::binary>>, hash), do: tail(rest, uint(rotate(bxor(hash, uint(byte * @p5)), 11) * @p1))
  defp tail(<<>>, hash), do: hash
  defp rotate(value, bits), do: uint(value <<< bits ||| value >>> (64 - bits))
  defp uint(value), do: band(value, @mask)
end
