defmodule Pulse.Storage.LogSegmentReaderTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log
  alias Pulse.Test.RandomTerms

  defp stream(blob, args, chunk) do
    {:ok, reader} = apply(NIF, :log_segment_reader_new, [blob | args])

    Stream.repeatedly(fn -> NIF.log_segment_reader_next(reader, chunk) end)
    |> Enum.take_while(&(&1 != :done))
    |> Enum.flat_map(fn {:ok, records} -> records end)
  end

  test "chunked decoding yields exactly the one-shot decode, in order, under every filter" do
    for _ <- 1..15 do
      records = RandomTerms.logs(:rand.uniform(12_000))
      {:ok, blob, _, _, _} = NIF.encode_log_segment_parquet(records)

      for args <- [
            [nil, nil, nil, [], []],
            [100, 1_000_000_000_000, nil, [], []],
            [nil, nil, "svc-1", [], []],
            [nil, nil, nil, [{"k", :re, "(?s:\\A(?:.*)\\z)"}], [{:contains, "a"}]]
          ] do
        {:ok, expected} = apply(NIF, :decode_log_segment_parquet, [blob | args])
        assert stream(blob, args, Enum.random([1, 100, 4096])) == expected
      end
    end
  end

  test "a chunk holds at least the requested records unless the segment ends" do
    records = for ts <- 1..10_000, do: %Log{timestamp_ns: ts, body: "x"}
    {:ok, blob, _, _, _} = NIF.encode_log_segment_parquet(records)
    {:ok, reader} = NIF.log_segment_reader_new(blob, nil, nil, nil, [], [])

    assert {:ok, first} = NIF.log_segment_reader_next(reader, 5000)
    assert length(first) >= 5000 and length(first) < 10_000
    assert {:ok, rest} = NIF.log_segment_reader_next(reader, 10_000)
    assert length(first) + length(rest) == 10_000
    assert :done = NIF.log_segment_reader_next(reader, 1)
    assert :done = NIF.log_segment_reader_next(reader, 1)
  end

  test "corrupt segments fall back instead of decoding partially" do
    assert :fallback = NIF.log_segment_reader_new("not parquet", nil, nil, nil, [], [])
  end
end
