defmodule Pulse.Storage.MetricPostingsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.Memory

  @key "pulse.metric.postings.v1"

  test "indexed native queries agree with complete reference scans despite hash collisions" do
    samples =
      for n <- 0..1199 do
        labels = %{"__name__" => "work", "env" => Enum.at(["dev", "prod", ""], rem(n, 3))}

        labels =
          case rem(n, 4) do
            0 -> labels
            1 -> Map.put(labels, "host", "")
            2 -> Map.put(labels, "host", "node")
            3 -> Map.put(labels, "host", "\"µ\\\n")
          end

        %MetricSample{series_id: 7, timestamp_ns: n, value: n / 1, labels: labels}
      end

    assert :ok = Memory.append(:metrics, "reference", samples)
    assert {:ok, blob, 0, 1199, 1200} = NIF.encode_metric_segment_parquet_indexed_v1(samples)
    assert :binary.match(blob, @key) != :nomatch

    for host <- ["", "node", "\"µ\\\n", "absent"],
        env <- ["", "dev", "prod"],
        extra <- [[], [{"host", :neq, "node"}], [{"host", :re, ".*"}], [{"env", :nre, "dev"}]],
        {lower, upper} <- [{nil, nil}, {99, 1000}, {1200, 1201}] do
      matchers = [{"host", :eq, host}, {"env", :eq, env}] ++ extra
      opts = [matchers: matchers, start_ts: lower, end_ts: upper]
      assert {:ok, expected} = Memory.query(:metrics, "reference", opts)
      assert {:ok, actual} = NIF.decode_metric_segment_parquet(blob, lower, upper, matchers)
      assert actual == Enum.sort_by(expected, & &1.timestamp_ns)
      assert {:ok, 1200, empty?} = NIF.metric_segment_footer_plan(blob, byte_size(blob), lower, upper, matchers)
      if empty?, do: assert(expected == [])
    end
  end

  test "unknown and damaged footer indexes fall back without changing rows or bounded-result failures" do
    samples = [
      %MetricSample{series_id: 1, timestamp_ns: 1, value: -0.0, labels: %{"host" => "a", "env" => "prod"}},
      %MetricSample{series_id: 1, timestamp_ns: 2, value: :stale, labels: %{"host" => "b", "env" => "dev"}},
      %MetricSample{series_id: 1, timestamp_ns: 3, value: :infinity, labels: %{}}
    ]

    assert {:ok, indexed, 1, 3, 3} = NIF.encode_metric_segment_parquet_indexed_v1(samples)
    assert :binary.match(indexed, @key) != :nomatch
    assert :binary.match(indexed, "50554c53454d5031") != :nomatch
    unknown = :binary.replace(indexed, @key, "pulse.metric.postings.v0", [:global])
    damaged = :binary.replace(indexed, "50554c53454d5031", "50554c53454d5030", [:global])

    for blob <- [indexed, unknown, damaged] do
      assert {:ok, decoded} = NIF.decode_metric_segment_parquet(blob, nil, nil, [])
      assert :erlang.term_to_binary(decoded, [:deterministic]) == :erlang.term_to_binary(samples, [:deterministic])
      assert {:ok, [first]} = NIF.decode_metric_segment_parquet(blob, nil, nil, [{"host", :eq, "a"}])
      assert <<first.value::float-64>> == <<0x8000000000000000::64>>

      assert {:ok, []} =
               NIF.decode_metric_segment_parquet_bounded(blob, nil, nil, [{"host", :eq, "a"}, {"env", :eq, "dev"}], 0)

      assert {:error, :query_sample_limit} =
               NIF.decode_metric_segment_parquet_bounded(blob, nil, nil, [{"env", :eq, "prod"}], 0)
    end
  end

  test "over-budget canonical dictionaries omit the optimization rather than omit samples" do
    samples =
      for n <- 1..513 do
        %MetricSample{series_id: 1, timestamp_ns: n, value: n / 1, labels: %{"__name__" => "m", "host" => "h#{n}"}}
      end

    assert {:ok, indexed, _, _, 512} = NIF.encode_metric_segment_parquet_indexed_v1(Enum.take(samples, 512))
    assert :binary.match(indexed, @key) != :nomatch
    assert {:ok, unindexed, _, _, 513} = NIF.encode_metric_segment_parquet_indexed_v1(samples)
    assert :binary.match(unindexed, @key) == :nomatch
    assert {:ok, [last]} = NIF.decode_metric_segment_parquet(unindexed, nil, nil, [{"host", :eq, "h513"}])
    assert last.timestamp_ns == 513
    assert {:ok, ^samples} = NIF.decode_metric_segment_parquet(unindexed, nil, nil, [])
  end
end
