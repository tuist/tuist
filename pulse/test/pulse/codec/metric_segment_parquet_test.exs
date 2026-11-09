defmodule Pulse.Codec.MetricSegmentParquetTest do
  # Round-trip tests for the metric Parquet codec. Mirrors the shape of
  # test/pulse/storage/s3_codec_test.exs on the logs side. Hits the
  # Rust NIF directly rather than going through Pulse.Storage, since
  # we're guarding the codec contract — not the storage adapter.
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3

  defp sample(ts, value, labels) when is_integer(ts) and is_map(labels) do
    %MetricSample{timestamp_ns: ts, value: value, labels: labels}
  end

  defp encode!(samples) do
    {:ok, payload, min_ts, max_ts, count} = NIF.encode_metric_segment_parquet(samples)
    {payload, min_ts, max_ts, count}
  end

  defp decode!(payload, opts \\ []) do
    start_ts = Keyword.get(opts, :start_ts)
    end_ts = Keyword.get(opts, :end_ts)
    matchers = Keyword.get(opts, :matchers, [])
    {:ok, records} = NIF.decode_metric_segment_parquet(payload, start_ts, end_ts, matchers)
    records
  end

  test "round-trips a single sample" do
    s = sample(1_700_000_000_000_000_000, 1.5, %{"__name__" => "up", "job" => "pulse"})
    {payload, min_ts, max_ts, count} = encode!([s])

    assert count == 1
    assert min_ts == s.timestamp_ns
    assert max_ts == s.timestamp_ns

    assert [decoded] = decode!(payload)
    assert decoded.timestamp_ns == s.timestamp_ns
    assert decoded.value == 1.5
    assert decoded.labels == s.labels
    # series_id is populated from StableHash on encode when the caller leaves it nil
    assert is_integer(decoded.series_id)
  end

  test "bounded footer statistics do not truncate long Unicode labels or time bounds" do
    prefix = String.duplicate("界🌍", 1000)
    samples = for ts <- [10, 20], do: sample(ts, ts / 1, %{"__name__" => "long", "context" => prefix <> "#{ts}"})
    {payload, 10, 20, 2} = encode!(samples)
    decoded = decode!(payload) |> Enum.sort_by(& &1.timestamp_ns)
    assert Enum.map(decoded, & &1.labels) == Enum.map(samples, & &1.labels)
    assert [kept] = decode!(payload, start_ts: 20, end_ts: 20, matchers: [{"context", :eq, prefix <> "20"}])
    assert kept.value == 20.0
    assert decode!(payload, start_ts: 21) == []
  end

  test "stale, NaN, and infinities survive randomized Parquet round trips" do
    :rand.seed(:exsss, {51, 7, 29})
    values = [:stale, :nan, :infinity, :negative_infinity, 0.0, -1.0, 17.25]

    for _ <- 1..20 do
      samples =
        for ts <- 1..100, do: sample(ts, Enum.at(values, :rand.uniform(length(values)) - 1), %{"__name__" => "special"})

      {payload, _, _, _} = encode!(samples)
      decoded = decode!(payload)
      assert Enum.map(decoded, &Map.delete(&1, :series_id)) == Enum.map(samples, &Map.delete(&1, :series_id))
      assert Enum.all?(decoded, &is_integer(&1.series_id))
      {again, _, _, _} = encode!(decoded)
      assert decode!(again) == decoded
    end
  end

  test "does not encode an unsupported value beside a finite sample" do
    labels = %{"__name__" => "up"}
    assert :fallback = NIF.encode_metric_segment_parquet([sample(1, 1.0, labels), sample(2, nil, labels)])
  end

  test "legacy stale markers remain bit-exact across decode and re-encode" do
    blob = File.read!(Path.expand("../../fixtures/metrics/non_finite.parquet", __DIR__))

    assert {:ok, [finite, stale] = samples} = NIF.decode_metric_segment_parquet(blob, nil, nil, [])
    assert finite.value == 1.0
    assert stale.value == :stale
    assert {:ok, ^samples} = NIF.decode_metric_segment_parquet_bounded(blob, nil, nil, [], 10)
    assert {:ok, ^samples} = S3.decode_segment(:metrics, blob, nil, nil, [])
    {encoded, _, _, _} = encode!(samples)
    assert decode!(encoded) == samples

    assert {:ok, [finite]} = NIF.decode_metric_segment_parquet(blob, nil, nil, [{"__name__", :eq, "safe"}])
    assert finite.value == 1.0
    assert finite.labels == %{"__name__" => "safe"}
  end

  test "consecutive label reuse compares canonical bytes rather than caller series IDs" do
    labels = [%{}, %{"svc" => "api"}, %{"svc" => "api"}, %{"svc" => "web"}, %{"svc" => "web"}, %{}, %{"svc" => "api"}]

    samples =
      labels
      |> Enum.with_index(1)
      |> Enum.map(fn {set, ts} -> %{sample(ts, ts * 1.0, set) | series_id: 42} end)

    {payload, _, _, _} = encode!(samples)
    assert decode!(payload) == samples

    for {op, value} <- [{:eq, "api"}, {:neq, "api"}, {:re, "api|web"}, {:nre, "api|web"}, {:eq, ""}] do
      expected =
        Enum.filter(samples, fn s ->
          actual = Map.get(s.labels, "svc", "")

          case op do
            :eq -> actual == value
            :neq -> actual != value
            :re -> Regex.match?(~r/^(api|web)$/, actual)
            :nre -> not Regex.match?(~r/^(api|web)$/, actual)
          end
        end)

      assert decode!(payload, matchers: [{"svc", op, value}]) == expected
    end

    assert {:error, :query_sample_limit} =
             NIF.decode_metric_segment_parquet_bounded(payload, nil, nil, [], 3)
  end

  test "repeated labels are shared in the decoded Erlang heap" do
    labels = %{"__name__" => "counter", "instance" => String.duplicate("x", 100)}
    {payload, _, _, _} = encode!(for ts <- 1..100, do: sample(ts, ts * 1.0, labels))
    [first, second | _] = decoded = decode!(payload)
    assert :erts_debug.same(first.labels, second.labels)
    assert Enum.all?(decoded, &(&1.labels == labels))
  end

  test "writer metadata reuse preserves varying IDs, Unicode labels, and invalid input rejection" do
    labels = %{"__name__" => "counter", "instance" => "é😀\"\\\n"}

    samples = [
      sample(1, 1, labels),
      %{sample(2, 2, labels) | series_id: 42},
      sample(3, 3, %{}),
      sample(4, 4, labels)
    ]

    {payload, _, _, _} = encode!(samples)
    decoded = decode!(payload) |> Enum.sort_by(& &1.timestamp_ns)
    assert Enum.map(decoded, & &1.labels) == Enum.map(samples, & &1.labels)
    assert Enum.at(decoded, 1).series_id == 42
    assert hd(decoded).series_id == List.last(decoded).series_id

    for invalid <- [%{labels | "instance" => :invalid}, %{bad: "value"}, nil] do
      assert :fallback = NIF.encode_metric_segment_parquet([hd(samples), %{hd(samples) | labels: invalid}])
    end
  end

  test "invalid label bytes cannot create unreadable segments or inject canonical labels" do
    valid = sample(1, 1.0, %{"__name__" => "safe"})

    for bytes <- [<<255>>, "a" <> <<255>> <> "injected" <> <<255>> <> "x", <<192, 175>>, <<237, 160, 128>>],
        labels <- [%{bytes => "value"}, %{"job" => bytes}] do
      invalid = %{valid | labels: labels}
      assert :fallback = NIF.encode_metric_segment_parquet([valid, valid, invalid])
      assert {:error, {:encode_failed, _}} = S3.encode_segment(:metrics, [invalid])
    end
  end

  test "record key sharing preserves duplicates, changing labels, and equal-time conflicting values" do
    labels = %{"__name__" => "counter"}

    samples = [
      %{sample(1, 1.0, labels) | series_id: 1},
      %{sample(1, 1.0, labels) | series_id: 1},
      %{sample(1, 2.0, labels) | series_id: 1},
      %{sample(1, 2.0, %{}) | series_id: 1},
      %{sample(2, 3.0, labels) | series_id: 2}
    ]

    {payload, _, _, _} = encode!(samples)
    decoded = decode!(payload)
    assert decoded == samples
    assert :erts_debug.same(hd(decoded), Enum.at(decoded, 1))
  end

  test "repeated long labels retain dictionary bytes rather than an expanded sample column" do
    long = String.duplicate("annotation", 100)
    labels = %{"__name__" => "counter", "annotation" => long}
    {payload, _, _, _} = encode!(for ts <- 1..2000, do: sample(ts, ts * 1.0, labels))
    [selected] = decode!(payload, start_ts: 1999, end_ts: 1999)
    assert selected.labels == labels
    assert :binary.referenced_byte_size(selected.labels["annotation"]) < 2 * byte_size(long)
  end

  test "batches sharing a label dictionary retain a single Erlang arena" do
    supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.ArenaSupervisor})
    long = String.duplicate("annotation", 100)
    labels = %{"__name__" => "counter", "annotation" => long}
    {payload, _, _, _} = encode!(for ts <- 1..2000, do: sample(ts, ts * 1.0, labels))

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        decoded = decode!(payload)
        :erlang.garbage_collect()
        size = :binary.referenced_byte_size(hd(decoded).labels["annotation"])
        {:binary, binaries} = Process.info(self(), :binary)
        count = binaries |> Enum.uniq_by(&elem(&1, 0)) |> Enum.count(&(elem(&1, 1) == size))
        {count, length(decoded)}
      end)

    assert Task.await(task) == {1, 2000}
  end

  test "dictionary-preserving reads support high-cardinality plain fallback pages" do
    samples =
      for ts <- 1..2000 do
        %{sample(ts, ts / 3, %{"instance" => "node-#{ts}", "annotation" => String.duplicate("é😀", 200)}) | series_id: 1}
      end

    {payload, _, _, _} = encode!(samples)
    assert decode!(payload) == samples
    assert decode!(payload, start_ts: 1000, end_ts: 1100) == Enum.slice(samples, 999, 101)
  end

  test "dictionary reuse preserves changing labels across adaptive row groups" do
    samples =
      for series <- 1..2, ts <- 1..9_000 do
        labels = %{"__name__" => "counter", "instance" => String.duplicate("node-#{series}", 100)}
        %{sample(ts, ts * 1.0, labels) | series_id: series}
      end

    {payload, 1, 9_000, 18_000} = encode!(samples)
    assert decode!(payload) == samples

    matchers = [{"instance", :eq, String.duplicate("node-2", 100)}]
    expected = Enum.filter(samples, &(&1.series_id == 2 and &1.timestamp_ns >= 8_999))
    assert decode!(payload, start_ts: 8_999, matchers: matchers) == expected

    assert {:error, :query_sample_limit} =
             NIF.decode_metric_segment_parquet_bounded(payload, nil, nil, matchers, 8_999)
  end

  test "same label set hashes to the same series_id across samples" do
    labels = %{"__name__" => "cpu", "instance" => "node-1"}
    a = sample(10, 0.1, labels)
    b = sample(20, 0.2, labels)
    {payload, _, _, _} = encode!([a, b])
    [d1, d2] = decode!(payload) |> Enum.sort_by(& &1.timestamp_ns)

    assert d1.series_id == d2.series_id
  end

  test "time filtering drops samples outside [start_ts, end_ts]" do
    labels = %{"__name__" => "req_total"}
    samples = for ts <- [10, 20, 30, 40, 50], do: sample(ts, 1.0, labels)
    {payload, _, _, _} = encode!(samples)

    kept = decode!(payload, start_ts: 20, end_ts: 40)
    assert Enum.map(kept, & &1.timestamp_ns) |> Enum.sort() == [20, 30, 40]
  end

  test "matcher :eq keeps only samples whose label equals value" do
    one = sample(1, 1.0, %{"__name__" => "x", "svc" => "api"})
    two = sample(2, 2.0, %{"__name__" => "x", "svc" => "web"})
    {payload, _, _, _} = encode!([one, two])

    assert [kept] = decode!(payload, matchers: [{"svc", :eq, "api"}])
    assert kept.labels["svc"] == "api"
  end

  test "matcher :re evaluates as a regex on the label value" do
    a = sample(1, 1.0, %{"__name__" => "x", "svc" => "api-east"})
    b = sample(2, 2.0, %{"__name__" => "x", "svc" => "web"})
    {payload, _, _, _} = encode!([a, b])

    assert [kept] = decode!(payload, matchers: [{"svc", :re, "^api"}])
    assert kept.labels["svc"] == "api-east"
  end

  test "a time filter that misses the whole segment returns [] (row-group pruning)" do
    labels = %{"__name__" => "x"}
    samples = for ts <- 100..200, do: sample(ts, 1.0, labels)
    {payload, _, _, _} = encode!(samples)

    # Both sides of the range are outside the segment's bounds.
    assert decode!(payload, start_ts: 500, end_ts: 1000) == []
    assert decode!(payload, start_ts: 0, end_ts: 50) == []
  end

  test "a time filter that bisects a multi-row-group segment preserves correctness" do
    # 20_000 samples > 8192 rows per row group → at least 3 row groups.
    # Filtering to the middle third exercises row-group pruning on the
    # bounding groups and a per-row scan on the middle one.
    labels = %{"__name__" => "y"}
    samples = for ts <- 1..20_000, do: sample(ts, 1.0, labels)
    {payload, _, _, _} = encode!(samples)

    kept = decode!(payload, start_ts: 7_000, end_ts: 13_000)
    kept_ts = kept |> Enum.map(& &1.timestamp_ns) |> Enum.sort()
    assert kept_ts == Enum.to_list(7_000..13_000)
  end

  test "encode->decode->encode->decode is idempotent on bytes from the second decode on" do
    # Mirrors the Pulse.Codec.NIF contract documented in AGENTS.md:
    # Parquet is a hard-error codec with no Elixir fallback, so we at
    # least pin round-trip idempotency on the stored form.
    base = for i <- 1..20, do: sample(i * 1_000_000_000, i * 1.0, %{"__name__" => "y", "k" => "v#{rem(i, 3)}"})

    {payload1, _, _, _} = encode!(base)
    decoded1 = decode!(payload1)
    {payload2, _, _, _} = encode!(decoded1)
    decoded2 = decode!(payload2)

    assert decoded1 == decoded2
  end
end
