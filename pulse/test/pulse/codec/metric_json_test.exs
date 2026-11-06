defmodule Pulse.Codec.MetricJSONTest do
  use Pulse.Test.Case, async: true

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.Record.Exemplar
  alias Pulse.Record.MetricSample

  # Exemplars render as their struct fields, only when present (as the MCP
  # tools' Elixir reference does).
  defp fields(sample) do
    fields = Map.take(sample, [:series_id, :timestamp_ns, :value, :labels, :otlp])

    fields =
      if is_nil(sample.start_timestamp_ms),
        do: fields,
        else: Map.put(fields, :start_timestamp_ms, sample.start_timestamp_ms)

    if sample.exemplars, do: Map.put(fields, :exemplars, Enum.map(sample.exemplars, &Map.from_struct/1)), else: fields
  end

  test "native response encoding matches the Elixir reference across randomized batches" do
    for _ <- 1..200 do
      labels = %{"__name__" => "counter", "unicode" => "é😀", "escaped" => "\"\\\n\r\t\x00\x1f"}

      samples =
        for i <- 1..:rand.uniform(30) do
          %MetricSample{
            series_id: Enum.random([nil, -9_223_372_036_854_775_808, i]),
            timestamp_ns: Enum.random([nil, -i, 9_223_372_036_854_775_807]),
            start_timestamp_ms: Enum.random([nil, -9_223_372_036_854_775_808, -i, i, 9_223_372_036_854_775_807]),
            value: Enum.random([nil, i, i / 3, -0.0, :nan, :stale, :infinity, :negative_infinity]),
            otlp: Enum.random([nil, %{"nested" => [%{"doubleValue" => -0.0}, %{"bytesValue" => "AP8="}]}]),
            labels: Enum.random([labels, %{}, Map.put(labels, "instance", "node-#{i}")]),
            exemplars:
              Enum.random([
                nil,
                [%Exemplar{labels: %{"trace_id" => "t#{i}"}, value: Enum.random([i / 7, :nan]), timestamp_ns: i}]
              ])
          }
        end

      assert {:ok, encoded} = NIF.encode_metric_samples(samples)
      assert JSON.decode!(encoded) == JSON.decode!(JSON.encode!(Enum.map(samples, &fields/1)))
    end
  end

  test "repeated label ranges remain valid through large output reallocations" do
    labels = %{"annotation" => String.duplicate("é\\\"", 1000)}
    samples = for i <- 1..100, do: %MetricSample{series_id: i, timestamp_ns: i, value: i * 1.0, labels: labels}
    assert {:ok, binary} = NIF.encode_metric_samples(samples)
    assert byte_size(binary) > 500_000
    assert JSON.decode!(binary) == JSON.decode!(JSON.encode!(Enum.map(samples, &fields/1)))
    assert {:ok, "[]"} = NIF.encode_metric_samples([])
  end

  test "invalid UTF-8 label keys and values fall back instead of emitting malformed JSON" do
    valid = %MetricSample{series_id: 1, timestamp_ns: 1, value: 1.0, labels: %{"key" => "valid"}}

    # Invalid leading bytes, overlong encodings, surrogate code points,
    # truncated sequences, and code points above the Unicode limit.
    for bytes <- [<<255>>, <<192, 175>>, <<237, 160, 128>>, <<226, 130>>, <<244, 144, 128, 128>>],
        labels <- [%{bytes => "value"}, %{"key" => bytes}] do
      invalid = %{valid | labels: labels}
      assert :fallback = NIF.encode_metric_samples([valid, valid, invalid])
      assert_raise ErlangError, fn -> JSON.encode!(Enum.map([invalid], &fields/1)) end
    end
  end

  test "improper sample lists fall back without returning a partial response" do
    sample = %MetricSample{series_id: 1, timestamp_ns: 1, value: 1.0, labels: %{}}
    assert :fallback = NIF.encode_metric_samples([sample | :invalid])
  end

  test "unsupported fields still fall back after a run of valid labels" do
    valid = %MetricSample{series_id: 1, timestamp_ns: 1, value: 1.0, labels: %{}}

    for invalid <- [
          %{valid | series_id: 1 <<< 80},
          %{valid | value: :invalid},
          %{valid | labels: %{"key" => :invalid}},
          %{valid | labels: %{atom_key: "value"}},
          %{},
          :invalid
        ] do
      assert :fallback = NIF.encode_metric_samples([valid, valid, invalid])
    end
  end
end
