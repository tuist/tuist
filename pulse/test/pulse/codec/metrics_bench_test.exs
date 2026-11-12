defmodule Pulse.Codec.MetricsBenchTest do
  # Micro-benchmarks for the metrics hot paths. Not part of the default
  # test run — `mix test --only bench` opts in. Each test prints the
  # measured numbers so a Rust refactor can compare before/after without
  # a heavier dependency like `benchee`.
  use Pulse.Test.Case, async: true

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.RemoteWrite.Push

  @moduletag :bench
  @moduletag timeout: 120_000

  @series_count 100
  @samples_per_series 100
  @iterations 20

  # ------- protobuf encoder (identical shape to the controller test) ------

  defp varint(v) when is_integer(v) and v >= 0 do
    if v < 128 do
      <<v>>
    else
      <<(v &&& 0x7F) ||| 0x80>> <> varint(v >>> 7)
    end
  end

  defp tag(field, wire), do: varint(field <<< 3 ||| wire)
  defp length_delim(field, bytes), do: tag(field, 2) <> varint(byte_size(bytes)) <> bytes
  defp varint_field(field, v), do: tag(field, 0) <> varint(v)
  defp fixed64_field(field, bytes), do: tag(field, 1) <> bytes

  defp encode_label(name, value), do: length_delim(1, name) <> length_delim(2, value)

  defp encode_sample(value, ts_ms), do: fixed64_field(1, <<value::little-float-64>>) <> varint_field(2, ts_ms)

  defp encode_series(labels, samples) do
    labels_bytes =
      Enum.map_join(labels, "", fn {n, v} ->
        length_delim(1, encode_label(n, v))
      end)

    samples_bytes =
      Enum.map_join(samples, "", fn {v, ts} ->
        length_delim(2, encode_sample(v, ts))
      end)

    labels_bytes <> samples_bytes
  end

  defp encode_write_request(series_list) do
    Enum.map_join(series_list, "", fn series ->
      length_delim(1, encode_series(series.labels, series.samples))
    end)
  end

  defp snappy(bytes) do
    {:ok, compressed} = :snappyer.compress(bytes)
    compressed
  end

  # ------- fixtures -------------------------------------------------------

  defp fixture_series do
    for i <- 0..(@series_count - 1) do
      %{
        labels: [
          {"__name__", "pulse_bench_metric"},
          {"instance", "node-#{i}"},
          {"job", "pulse-bench"},
          {"service", "api"}
        ],
        samples:
          for s <- 0..(@samples_per_series - 1) do
            # Base timestamp 2026-10-01T00:00:00Z in ms, 15s step.
            {s * 1.0, 1_790_000_000_000 + s * 15_000}
          end
      }
    end
  end

  defp fixture_compressed_write_request do
    fixture_series() |> encode_write_request() |> snappy()
  end

  defp fixture_samples do
    base = 1_790_000_000_000_000_000

    for i <- 0..(@series_count - 1),
        s <- 0..(@samples_per_series - 1) do
      %MetricSample{
        series_id: i,
        timestamp_ns: base + s * 15_000_000_000,
        value: s * 1.0,
        labels: %{
          "__name__" => "pulse_bench_metric",
          "instance" => "node-#{i}",
          "job" => "pulse-bench",
          "service" => "api"
        }
      }
    end
  end

  defp fixture_metric_parquet do
    samples = fixture_samples()
    {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet(samples)
    blob
  end

  # ------- bench harness --------------------------------------------------

  defp bench(label, fun) do
    # Warm-up once so the first run's JIT / cache cost does not skew min.
    fun.()

    runs =
      for _ <- 1..@iterations do
        {us, _} = :timer.tc(fun)
        us
      end

    sorted = Enum.sort(runs)
    min = Enum.min(sorted)
    max = Enum.max(sorted)
    median = Enum.at(sorted, div(length(sorted), 2))
    mean = div(Enum.sum(sorted), length(sorted))

    IO.puts(
      "bench: #{label} | iter=#{@iterations} | " <>
        "min=#{min}µs median=#{median}µs mean=#{mean}µs max=#{max}µs | " <>
        "total samples=#{@series_count * @samples_per_series}"
    )

    sorted
  end

  # ------- benchmarks -----------------------------------------------------

  test "decode_remote_write + fan-out to %MetricSample{}" do
    body = fixture_compressed_write_request()

    bench("decode_remote_write + Push.expand", fn ->
      {:ok, samples, 0} = Push.decode_protobuf(body, 16 * 1024 * 1024)
      length(samples)
    end)
  end

  test "query_metrics JSON response encode: Elixir path (JSON.encode!)" do
    samples = fixture_samples()

    bench("encode samples -> JSON (Elixir)", fn ->
      body =
        samples
        |> Enum.map(fn s ->
          %{
            "series_id" => s.series_id,
            "timestamp_ns" => s.timestamp_ns,
            "value" => s.value,
            "labels" => s.labels
          }
        end)
        |> JSON.encode!()

      byte_size(body)
    end)
  end

  test "query_metrics JSON response encode: Rust fast path" do
    samples = fixture_samples()

    bench("encode samples -> JSON (Rust)", fn ->
      {:ok, body} = NIF.encode_metric_samples(samples)
      byte_size(body)
    end)
  end

  test "decode_metric_segment_parquet" do
    blob = fixture_metric_parquet()

    bench("decode_metric_segment_parquet", fn ->
      {:ok, samples} = NIF.decode_metric_segment_parquet(blob, nil, nil, [])
      length(samples)
    end)
  end

  defp fixture_single_series_parquet(n_samples) do
    labels = %{"__name__" => "pulse_bench_single", "instance" => "node-0"}
    base = 1_790_000_000_000_000_000

    samples =
      for s <- 0..(n_samples - 1) do
        %MetricSample{
          series_id: 1,
          timestamp_ns: base + s * 15_000_000_000,
          value: s * 1.0,
          labels: labels
        }
      end

    {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet(samples)
    {blob, base}
  end

  test "decode_metric_segment_parquet with filter that prunes all but one row group" do
    # 20_000 samples > `max_row_group_size = 8192` row group cap, so
    # the segment splits into 3 row groups. All samples belong to a
    # single series, so each row group covers a distinct and contiguous
    # timestamp window: group 0 ≈ ts 0..8191, group 1 ≈ 8192..16383,
    # group 2 ≈ 16384..19999. Filtering to the middle group's window
    # exercises the row-group min/max pruning in `decode`.
    {blob, base} = fixture_single_series_parquet(20_000)
    start_ts = base + 8_192 * 15_000_000_000
    end_ts = base + 16_383 * 15_000_000_000

    bench("decode_metric_segment_parquet (prune 2/3 row groups)", fn ->
      {:ok, samples} = NIF.decode_metric_segment_parquet(blob, start_ts, end_ts, [])
      length(samples)
    end)
  end

  test "decode_metric_segment_parquet with a narrow time filter (per-row short-circuit)" do
    blob = fixture_metric_parquet()
    # The fixture sorts by `(series_id, timestamp_ns)`, so every row
    # group covers the full timestamp range. On this workload the
    # time filter exercises the per-row short-circuit (continue
    # before the labels arena slice is parsed), not row-group
    # pruning — see the correctness test
    # "a time filter that bisects a multi-row-group segment …" for a
    # workload where row-group pruning actually fires.
    base = 1_790_000_000_000_000_000
    start_ts = base
    end_ts = base + div(@samples_per_series, 5) * 15_000_000_000

    bench("decode_metric_segment_parquet (filtered 20%)", fn ->
      {:ok, samples} = NIF.decode_metric_segment_parquet(blob, start_ts, end_ts, [])
      length(samples)
    end)
  end
end
