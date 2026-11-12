defmodule Pulse.PromQL.DiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.PromQL.Discovery
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.Memory

  @min -9_223_372_036_854_775_808
  @max 9_223_372_036_854_775_807

  defp native(mode, key, selectors, blobs, start \\ @min, finish \\ @max) do
    assert {:ok, state} = NIF.metric_discovery_new(mode, key, start, finish, selectors)
    Enum.each(blobs, fn blob -> assert {:ok, _} = NIF.metric_discovery_add(state, blob) end)
    assert {:ok, json} = NIF.metric_discovery_finish(state)
    Pulse.JSON.decode!(json)
  end

  # Each window/selector owns its fixture and the normal test deadline. Keep
  # all 45 mode comparisons without one test accumulating every scan's wait.
  for {start, finish} <- [{0, 1199}, {99, 700}, {1200, 1201}],
      {selectors, index} <-
        Enum.with_index([
          [],
          [[{"__name__", :eq, "work"}, {"host", :eq, ""}]],
          [[{"__name__", :re, "work|other"}, {"env", :nre, "dev"}, {"host", :neq, "node"}]],
          [[{"__name__", :eq, "work"}, {"host", :re, "node|µ.*"}], [{"__name__", :eq, "other"}, {"env", :eq, "dev"}]]
        ]) do
    @tag :native_reference_matrix
    @tag selectors: selectors, window: {start, finish}
    test "native labels-only scans agree with the reference for #{start}..#{finish}, selector #{index}", %{
      selectors: selectors,
      window: {start, finish}
    } do
      rows =
        for n <- 0..1199 do
          labels = %{
            "__name__" => if(rem(n, 2) == 0, do: "work", else: "other"),
            "env" => Enum.at(["dev", "prod", ""], rem(n, 3))
          }

          labels =
            case rem(n, 4) do
              0 -> labels
              1 -> Map.put(labels, "host", "")
              2 -> Map.put(labels, "host", "node")
              _ -> Map.put(labels, "host", "µ\"\\\n")
            end

          %MetricSample{series_id: 7, timestamp_ns: n, value: :stale, labels: labels}
        end

      :ok = Memory.append(:metrics, "reference", rows)

      blobs =
        for chunk <- Enum.chunk_every(rows, 173) do
          assert {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet_indexed_v1(chunk)
          blob
        end

      for {mode, key} <- [{"names", ""}, {"values", "host"}, {"values", "env"}, {"series", ""}],
          mode != "series" or selectors != [] do
        assert {:ok, expected} =
                 Discovery.reference(Memory, "reference", mode, key, selectors, start_ts: start, end_ts: finish)

        expected = Pulse.JSON.decode!(expected)
        assert native(mode, key, selectors, blobs, start, finish) == expected
        assert native(mode, key, selectors, Enum.reverse(blobs, blobs), start, finish) == expected
      end
    end
  end

  test "repeated samples do not consume distinct series capacity and 5000 succeeds while 5001 fails whole" do
    rows =
      for n <- 1..5001,
          do: %MetricSample{timestamp_ns: n, value: :nan, labels: %{"__name__" => "wide", "host" => "h#{n}"}}

    assert {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet_v2(rows)
    assert length(native("values", "host", [], [blob], 1, 5000)) == 5000
    assert {:ok, state} = NIF.metric_discovery_new("values", "host", 1, 5001, [])
    assert {:error, :query_resource_limit} = NIF.metric_discovery_add(state, blob)
    assert :fallback = NIF.metric_discovery_finish(state)
    dense = List.duplicate(hd(rows), 20_000)
    assert {:ok, dense_blob, _, _, _} = NIF.encode_metric_segment_parquet_v2(dense)
    assert native("series", "", [[{"__name__", :eq, "wide"}]], [dense_blob]) == [hd(rows).labels]
  end

  test "escaped output can exceed its ceiling below the raw dictionary ceiling" do
    rows =
      for n <- 1..2000,
          do: %MetricSample{timestamp_ns: n, value: 1.0, labels: %{"host" => "#{n}" <> String.duplicate(<<0>>, 200)}}

    assert {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet_v2(rows)
    assert {:ok, state} = NIF.metric_discovery_new("values", "host", 1, 2000, [])
    assert {:error, :query_resource_limit} = NIF.metric_discovery_add(state, blob)
    :ok = Memory.append(:metrics, "escaped", rows)
    assert {:error, :query_resource_limit} = Discovery.reference(Memory, "escaped", "values", "host", [], [])
  end

  test "unsafe canonical UTF8 cannot be written and invalid stored inputs poison state" do
    rows = [%MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"__name__" => "bad", "host" => <<254>>}}]
    assert :fallback = NIF.encode_metric_segment_parquet_v2(rows)
    :ok = Memory.append(:metrics, "corrupt", rows)

    assert {:error, :invalid_stored_sample} =
             Discovery.reference(Memory, "corrupt", "names", "", [[{"__name__", :eq, "other"}]], [])

    assert {:ok, state} = NIF.metric_discovery_new("names", "", 0, 2, [[{"__name__", :eq, "other"}]])
    assert {:error, :invalid_stored_sample} = NIF.metric_discovery_add(state, "invalid stored parquet")
    assert :fallback = NIF.metric_discovery_finish(state)
    assert {:ok, empty} = NIF.metric_discovery_new("names", "", 0, 2, [])
    assert :ok = NIF.metric_discovery_abort(empty)
    assert :fallback = NIF.metric_discovery_finish(empty)
    assert {:error, :invalid_stored_sample} = NIF.metric_segment_parquet_row_count("invalid")
  end

  test "constructors fence wrong modes, unbounded selectors, empty matching and regex floods" do
    assert NIF.metric_discovery_api_version() == 1

    for {mode, key, selectors} <- [
          {"bogus", "", []},
          {"values", "", []},
          {"names", "host", []},
          {"series", "", []},
          {"names", "", [[{"host", :re, ".*"}]]},
          {"names", "", List.duplicate([{"host", :eq, "a"}], 17)},
          {"names", "", [List.duplicate({"host", :eq, "a"}, 65)]},
          {"names", "", [List.duplicate({"host", :re, "a"}, 9)]}
        ] do
      assert :fallback = NIF.metric_discovery_new(mode, key, @min, @max, selectors)
    end

    assert :fallback = NIF.metric_discovery_new("names", "", 2, 1, [])

    for selectors <- [["sum(work)"], ["work[1m]"], [~s({host=""})], List.duplicate("work", 17)] do
      assert {:error, _} = Discovery.query("reference", "names", "", selectors)
    end
  end
end
