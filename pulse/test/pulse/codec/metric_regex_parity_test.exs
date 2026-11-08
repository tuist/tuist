defmodule Pulse.Codec.MetricRegexParityTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.Memory

  test "missing, empty, and present labels agree between memory and Parquet" do
    Memory.reset()
    labels = [%{}, %{"job" => ""}, %{"job" => "api"}, %{"job" => "web"}, %{"job" => "api\nweb"}, %{"job" => "١"}]

    records =
      for {extra, index} <- Enum.with_index(labels),
          do: %MetricSample{timestamp_ns: index + 1, value: index * 1.0, labels: Map.put(extra, "__name__", "m")}

    :ok = Memory.append(:metrics, "parity", records, [])
    {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet(records)

    for pattern <- [".*", "api|", "api", "", "\\d", "a.*"], op <- [:re, :nre] do
      matchers = [{"job", op, "(?s:\\A(?:#{pattern})\\z)"}]
      {:ok, expected} = Memory.query(:metrics, "parity", matchers: matchers)
      assert {:ok, actual} = NIF.decode_metric_segment_parquet(blob, nil, nil, matchers)
      assert Enum.sort(Enum.map(actual, & &1.value)) == Enum.sort(Enum.map(expected, & &1.value))
    end
  end

  test "Perl classes use Prometheus ASCII semantics" do
    assert NIF.match_metric_regex("\\d", "1")
    refute NIF.match_metric_regex("\\d", "١")
    assert NIF.match_metric_regex("\\w", "a")
    refute NIF.match_metric_regex("\\w", "é")
    refute NIF.match_metric_regex("\\s", "\u00A0")
  end

  test "unsupported classes reject while Go literal members never become set operators" do
    for pattern <- ["[a--b]", "[z-a]"] do
      assert :error = NIF.validate_metric_regex(pattern)
    end

    for pattern <- ["[a&&b]", "[a~~b]", "[]a&&b]", "[^]a&&b]", "[[ab]]", "[--x]"] do
      assert :ok = NIF.validate_metric_regex(pattern)
    end

    for value <- ["a", "&", "b"], do: assert(NIF.match_metric_regex("[a&&b]", value))
    refute NIF.match_metric_regex("[a&&b]", "z")
    assert NIF.match_metric_regex("[[ab]]", "a]")
    refute NIF.match_metric_regex("[[ab]]", "a")
    assert :ok = NIF.validate_metric_regex("[[:alpha:]]")
    assert NIF.match_metric_regex("[[:alpha:]]", "a")
    assert :ok = NIF.validate_metric_regex("a&&b")
  end

  test "unsupported regexes fail rather than negating an ignored filter" do
    record = %MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"__name__" => "m", "job" => "api"}}
    {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet([record])

    for op <- [:re, :nre] do
      assert :fallback = NIF.decode_metric_segment_parquet(blob, nil, nil, [{"job", op, "(?!api).*"}])
    end
  end

  test "the decoder stops materializing at its sample budget" do
    records = for i <- 1..100, do: %MetricSample{timestamp_ns: i, value: i * 1.0, labels: %{"__name__" => "m"}}
    {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet(records)
    assert {:error, :query_sample_limit} = NIF.decode_metric_segment_parquet_bounded(blob, nil, nil, [], 10)
    assert {:ok, samples} = NIF.decode_metric_segment_parquet_bounded(blob, 90, 100, [], 11)
    assert length(samples) == 11
    assert {:ok, []} = NIF.decode_metric_segment_parquet_bounded(blob, nil, nil, [{"__name__", :eq, "other"}], 0)
  end
end
