defmodule Pulse.Storage.S3.MetricSummaryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment

  defp segment(names) do
    Segment.build("segment.parquet", 1, 2, length(names))
    |> Segment.summarize_metrics(Enum.map(names, &%MetricSample{labels: %{"__name__" => &1}}))
  end

  test "summaries describe exactly the names surviving segment encoding" do
    records =
      for {name, i} <- Enum.with_index(["cpu", "memory", "cpu", ""]),
          do: %MetricSample{timestamp_ns: i + 1, value: i * 1.0, labels: %{"__name__" => name}}

    records = [%MetricSample{timestamp_ns: 9, value: 0.0, labels: %{}} | records]
    summary = Segment.build("x", 1, 9, length(records)) |> Segment.summarize_metrics(records)
    assert {:ok, blob, _, _, _} = NIF.encode_metric_segment_parquet(records)
    assert {:ok, decoded} = NIF.decode_metric_segment_parquet(blob, nil, nil, [])
    names = decoded |> Enum.map(&Map.get(&1.labels, "__name__", "")) |> Enum.uniq() |> Enum.sort()
    assert summary.metric_names == names
  end

  test "complete names round-trip without changing the manifest schema" do
    summary = segment(["requests_total", "cpu", "cpu"])
    assert summary.metric_names == ["cpu", "requests_total"]

    assert {:ok, decoded} =
             summary
             |> List.wrap()
             |> then(&Manifest.merge(Manifest.new(), &1))
             |> Manifest.encode()
             |> IO.iodata_to_binary()
             |> Manifest.decode()

    assert decoded.segments == [summary]
    assert Segment.matches_metric_name?(summary, [{"__name__", :eq, "cpu"}])
    refute Segment.matches_metric_name?(summary, [{"__name__", :eq, "memory"}])
    assert Segment.matches_metric_name?(summary, [{"job", :eq, "api"}, {"__name__", :re, ".*"}])
  end

  test "older, malformed, and oversized summaries always remain eligible" do
    for names <- [nil, "cpu", [123], Enum.map(1..129, &"metric_#{&1}"), [String.duplicate("x", 257)]] do
      assert {:ok, summary} = Segment.from_wire(%{"k" => "x", "mn" => 1, "mx" => 2, "n" => names})
      assert summary.metric_names == nil
      assert Segment.matches_metric_name?(summary, [{"__name__", :eq, "anything"}])
    end

    assert segment(Enum.map(1..129, &"metric_#{&1}")).metric_names == nil
    assert segment([String.duplicate("x", 257)]).metric_names == nil
  end

  test "remote-write-sized name sets prune through a bounded bloom without dropping present names" do
    present = Enum.map(1..1000, &"kube_metric_#{&1}_bytes")
    absent = Enum.map(1..1000, &"node_metric_#{&1}_bytes")
    summary = segment(present)
    assert summary.metric_names == nil
    assert byte_size(summary.metric_name_bloom) == 1024

    assert {:ok, %Manifest{segments: [decoded]}} =
             %Manifest{segments: [summary]} |> Manifest.encode() |> IO.iodata_to_binary() |> Manifest.decode()

    assert decoded == summary

    for candidate <- [summary, decoded] do
      assert Enum.all?(present, &Segment.matches_metric_name?(candidate, [{"__name__", :eq, &1}]))
      # At the 1 KiB cap: about 2.4% false positives at eight bits per name.
      assert Enum.count(absent, &Segment.matches_metric_name?(candidate, [{"__name__", :eq, &1}])) < 60
    end

    # PromQL pushes anchored literal alternations; any present alternative keeps it.
    re = fn names -> {"__name__", :re, "(?s:\\A(?:" <> Enum.join(names, "|") <> ")\\z)"} end
    assert Segment.matches_metric_name?(summary, [re.([hd(absent), hd(present)])])
    refute Segment.matches_metric_name?(summary, [re.(Enum.take(absent, 1))])

    # Matchers a bloom cannot decide never prune.
    for matcher <- [{"__name__", :neq, hd(present)}, {"__name__", :re, "(?s:\\A(?:node_.*)\\z)"}, {"__name__", :eq, ""}],
        do: assert(Segment.matches_metric_name?(summary, [matcher]))

    # Small sets keep their exact list; larger, invalid or long-name sets stay unknown.
    assert segment(Enum.take(present, 128)).metric_name_bloom == nil
    assert byte_size(segment(Enum.take(present, 129)).metric_name_bloom) == 512

    for names <- [Enum.map(1..2049, &"m#{&1}"), [<<0xFF>> | present], [String.duplicate("x", 257) | present]] do
      unknown = segment(names)
      assert {unknown.metric_names, unknown.metric_name_bloom} == {nil, nil}
    end
  end

  test "older, malformed and missing name blooms remain eligible" do
    bits = segment(Enum.map(1..300, &"m#{&1}")).metric_name_bloom

    for encoded <- [
          nil,
          7,
          "not base64",
          Base.encode64(<<1, 2, 3>>),
          Base.encode64(<<0::8192>>),
          Base.encode64(bits <> <<1>>)
        ] do
      assert {:ok, summary} = Segment.from_wire(%{"k" => "x", "mn" => 1, "mx" => 2, "nb" => encoded})
      assert summary.metric_name_bloom == nil
      assert Segment.matches_metric_name?(summary, [{"__name__", :eq, "anything"}])
    end
  end

  test "all exact name matchers must be satisfiable; absent names use empty string" do
    summary = Segment.build("x", 1, 2, 1) |> Segment.summarize_metrics([%MetricSample{}])
    assert summary.metric_names == [""]
    assert Segment.matches_metric_name?(summary, [{"__name__", :eq, ""}])
    refute Segment.matches_metric_name?(segment(["cpu"]), [{"__name__", :eq, "cpu"}, {"__name__", :eq, "other"}])
  end

  test "selective queries eliminate known irrelevant objects while keeping unknown segments" do
    segments = for i <- 1..100, do: %{segment(["metric_#{i}"]) | key: "#{i}.parquet", byte_size: 4096}
    legacy = %{Segment.build("legacy.parquet", 1, 2, 10) | byte_size: 4096}
    candidates = [legacy | segments]
    selected = Enum.filter(candidates, &Segment.matches_metric_name?(&1, [{"__name__", :eq, "metric_42"}]))
    assert Enum.map(selected, & &1.key) == ["legacy.parquet", "42.parquet"]
    assert Enum.sum(Enum.map(selected, & &1.byte_size)) == 8192
    assert Enum.sum(Enum.map(candidates, & &1.byte_size)) == 413_696
  end

  test "shared name sets and a dictionary budget bound manifest overhead" do
    names = Enum.map(1..128, &"metric_#{&1}_#{String.duplicate("x", 40)}")
    base = for i <- 1..1000, do: %{segment(names) | key: "#{i}.parquet"}
    encoded = IO.iodata_to_binary(Manifest.encode(%Manifest{segments: base}))
    bare = IO.iodata_to_binary(Manifest.encode(%Manifest{segments: Enum.map(base, &%{&1 | metric_names: nil})}))
    assert byte_size(encoded) - byte_size(bare) < 20_000
    assert {:ok, decoded} = Manifest.decode(encoded)
    assert Enum.all?(decoded.segments, &(&1.metric_names == Enum.sort(names)))

    unique = for i <- 1..1000, do: %{segment(Enum.map(names, &"#{i}#{&1}")) | key: "#{i}.parquet"}
    wire = unique |> then(&%Manifest{segments: &1}) |> Manifest.encode() |> IO.iodata_to_binary() |> JSON.decode!()
    assert byte_size(JSON.encode!(wire["names"])) <= 65_536
    assert {:ok, decoded} = Manifest.decode(JSON.encode!(wire))
    fallback = Enum.filter(decoded.segments, &is_nil(&1.metric_names))
    assert fallback != []
    assert Enum.all?(fallback, &(byte_size(&1.metric_name_bloom) <= 256))
    assert Enum.count(fallback, &Segment.matches_metric_name?(&1, [{"__name__", :eq, "not-present"}])) < 30

    by_key = Map.new(decoded.segments, &{&1.key, &1})

    for source <- unique, name <- source.metric_names do
      assert Segment.matches_metric_name?(by_key[source.key], [{"__name__", :eq, name}])
    end

    {cached, cache} = Manifest.encode(%Manifest{segments: unique}, %{})
    assert Manifest.decode(IO.iodata_to_binary(cached)) == {:ok, decoded}
    trimmed = %Manifest{segments: Enum.take(unique, -3)}
    {cached, _} = Manifest.encode(trimmed, cache)

    assert Manifest.decode(IO.iodata_to_binary(cached)) ==
             Manifest.decode(IO.iodata_to_binary(Manifest.encode(trimmed)))
  end

  test "older inline sets and invalid dictionary references remain safe" do
    for wire <- [%{"ni" => 999}, %{"ni" => -1}, %{"ni" => "0"}, %{"ni" => 0}] do
      entry = Map.merge(%{"k" => "x", "mn" => 1, "mx" => 2}, wire)
      assert {:ok, manifest} = Manifest.decode(JSON.encode!(%{"v" => 1, "s" => [entry]}))
      assert hd(manifest.segments).metric_names == nil
    end

    entry = %{"k" => "x", "mn" => 1, "mx" => 2, "n" => ["cpu"]}
    assert {:ok, manifest} = Manifest.decode(JSON.encode!(%{"v" => 1, "s" => [entry]}))
    assert hd(manifest.segments).metric_names == ["cpu"]
  end
end
