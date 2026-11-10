defmodule Pulse.Storage.MetricMetadataCodecTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.S3
  alias Pulse.Storage.SortOrder

  @directory Path.expand("../../fixtures/metrics", __DIR__)

  test "native metric metadata API is required and legacy six-column files remain readable" do
    assert NIF.metric_metadata_api_version() == 2
    assert NIF.otlp_metrics_api_version() == 2
    assert NIF.metric_postings_api_version() == 1
    assert NIF.metric_reader_api_version() == 1
    assert :ok = NIF.ensure_metric_metadata_api!()
    legacy = File.read!(Path.join(@directory, "legacy_metric.parquet"))
    assert {:ok, [sample]} = decode(legacy)
    assert sample.otlp == nil
    assert sample.labels == %{"__name__" => "legacy_metric"}
    assert sample.series_id == 42
    assert <<sample.value::float-64>> == <<0x8000000000000000::64>>
    assert {:ok, reader} = NIF.metric_segment_reader_new(legacy, nil, nil, [])
    assert {:ok, [^sample]} = NIF.metric_segment_reader_next(reader, 1)
    assert :done = NIF.metric_segment_reader_next(reader, 0)

    for filename <- ["invalid_otlp_type.parquet", "invalid_otlp_value.parquet"] do
      blob = File.read!(Path.join(@directory, filename))
      assert :fallback = decode(blob)

      result =
        case NIF.metric_segment_reader_new(blob, nil, nil, []) do
          {:ok, reader} -> NIF.metric_segment_reader_next(reader, 4096)
          :fallback -> :fallback
        end

      assert :fallback = result
    end
  end

  test "roundtrip, canonical order and JSON preserve nested metadata and signed zero" do
    for _ <- 1..60 do
      samples =
        for sign <- [0.0, -0.0] do
          %MetricSample{
            series_id: 17,
            timestamp_ns: 123,
            value: sign,
            labels: %{"__name__" => "metric", "service" => "example"},
            otlp: %{
              "source" => %{
                "numbers" => [sign, "9223372036854775807"],
                "attributes" => [%{"key" => "bytes", "value" => %{"bytesValue" => "AP8="}}]
              },
              "name" => "é😀"
            }
          }
        end

      {:ok, blob, 123, 123, 2} = NIF.encode_metric_segment_parquet(samples)
      {:ok, first} = decode(blob)
      {:ok, next, _, _, _} = NIF.encode_metric_segment_parquet(first)
      {:ok, second} = decode(next)
      assert :erlang.term_to_binary(first, [:deterministic]) == :erlang.term_to_binary(second, [:deterministic])
      assert Enum.map(first, fn sample -> <<sample.value::float-64>> end) == [<<0::64>>, <<0x8000000000000000::64>>]
      assert :erlang.term_to_binary(first, [:deterministic]) == :erlang.term_to_binary(samples, [:deterministic])
      assert SortOrder.sort(samples, :metrics) == SortOrder.sort(Enum.reverse(samples), :metrics)
      assert {:ok, json} = NIF.encode_metric_samples(first)
      assert Enum.map(Pulse.JSON.decode!(json), & &1["otlp"]) == Enum.map(samples, & &1.otlp)
    end
  end

  test "metadata participates in fingerprints, while nil preserves the historical fingerprint" do
    sample = %MetricSample{series_id: 1, timestamp_ns: 2, value: 3.0, labels: %{"__name__" => "m"}}
    old = [Map.take(sample, [:timestamp_ns, :value, :labels])]

    expected =
      :crypto.hash(:sha256, :erlang.term_to_binary(old, [:deterministic]))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    assert S3.caller_content_hash(:metrics, [sample]) == {:ok, expected}
    assert {:ok, a} = S3.caller_content_hash(:metrics, [%{sample | otlp: %{"type" => "int"}}])
    assert {:ok, b} = S3.caller_content_hash(:metrics, [%{sample | otlp: %{"type" => "double"}}])
    assert a != b
    assert {:ok, c} = S3.caller_content_hash(:metrics, [%{sample | start_timestamp_ms: -1}])
    assert {:ok, d} = S3.caller_content_hash(:metrics, [%{sample | start_timestamp_ms: 1}])
    assert c != d
    assert c != expected
    assert d != expected
  end

  test "normal compaction-sized scalar batches do not acquire the raw result-text cap" do
    sample = %MetricSample{
      timestamp_ns: 1,
      value: 1.0,
      labels: %{"__name__" => "m", "pod" => String.duplicate("a", 160)}
    }

    samples = List.duplicate(sample, 100_000)
    assert {:ok, _blob, 1, 1, 100_000} = NIF.encode_metric_segment_parquet(samples)
    assert {:error, :query_result_limit} = NIF.encode_metric_samples(samples)
  end

  test "metadata and response expansion fail before allocating oversized metadata columns or result binary" do
    sample = %MetricSample{
      timestamp_ns: 1,
      value: :infinity,
      labels: %{"__name__" => "m"},
      otlp: %{"repeated" => String.duplicate("\0", 8192)}
    }

    samples = List.duplicate(sample, 400)
    assert {:error, :payload_too_large} = NIF.encode_metric_segment_parquet(samples)
    assert {:error, :payload_too_large} = S3.encode_segment(:metrics, samples)
    assert {:error, :query_result_limit} = NIF.encode_metric_samples(samples)
  end

  defp decode(blob), do: NIF.decode_metric_segment_parquet(blob, nil, nil, [])
end
