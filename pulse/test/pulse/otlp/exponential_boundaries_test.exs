defmodule Pulse.OTLP.ExponentialBoundariesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.JSON
  alias Pulse.OTLP.Metrics
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Test.OTLPMetricFixture, as: Fixture

  @directory "test/fixtures/otlp/exponential_boundaries"

  test "public wire and JSON preserve the source and match independent mathematical boundary controls" do
    assert {:ok, rows, 0} = Metrics.decode(JSON.decode!(File.read!(Path.join(@directory, "request.json")), :metrics))
    assert {:ok, wire, 0} = Metrics.decode_protobuf(File.read!(Path.join(@directory, "request.protobuf")))
    assert bits(rows) == bits(wire)
    geometry = @directory |> Path.join("geometry.json") |> File.read!() |> Pulse.JSON.decode!()
    grouped = Enum.group_by(rows, & &1.labels["case"])
    assert map_size(grouped) == length(geometry)

    for control <- geometry do
      samples = Map.fetch!(grouped, control["name"])
      upper = from_bits(control["bound_bits"])
      # A projected signed zero is canonical; original source bits are not changed.
      upper = if upper == 0.0, do: 0.0, else: upper
      candidates = Enum.filter(samples, &(&1.otlp["projection"]["component"] == "bucket" and &1.value == 1.0))
      actual = candidates |> hd() |> Map.fetch!(:labels) |> Map.fetch!("le") |> parse_bound()
      assert close?(actual, upper), inspect({control, actual})
      assert List.last(candidates).labels["le"] == "+Inf"
      assert hd(samples).otlp["point"]["scale"] == control["scale"]
      assert hd(samples).otlp["point"]["count"] == "1"
      assert hd(samples).timestamp_ns == 1_700_000_000_123_456_789
    end

    assert {:ok, blob, _, _} = S3.encode_segment(:metrics, rows)
    assert {:ok, stored} = S3.decode_segment(:metrics, blob, nil, nil, [])
    expected = rows |> Enum.map(&bits(&1.otlp)) |> Enum.sort()
    assert expected == stored |> Enum.map(&bits(&1.otlp)) |> Enum.sort()
    assert {:ok, _} = NIF.encode_metric_samples(stored)
  end

  test "public histogram iterators expose endpoint conventions and the finite overflow sentinel" do
    geometry = @directory |> Path.join("geometry.json") |> File.read!() |> Pulse.JSON.decode!()
    public = Enum.filter(geometry, &Map.has_key?(&1, "prometheus_bound_bits"))
    assert length(public) > 500

    for control <- public do
      mathematical = from_bits(control["bound_bits"])
      observed = from_bits(control["prometheus_bound_bits"])
      inclusive? = observed == :infinity or (is_float(observed) and observed > 0)
      assert control["prometheus_upper_inclusive"] == inclusive?

      if mathematical in [:infinity, :negative_infinity] and is_float(observed) do
        <<maximum::float-64>> = <<0x7FEFFFFFFFFFFFFF::64>>
        assert abs(observed) == maximum
      else
        assert close?(mathematical, observed), inspect(control)
      end
    end

    assert Enum.any?(public, &(&1["direct_exp2_bits"] != &1["bound_bits"]))
  end

  test "frozen public inputs and linked library identities match their checksum index" do
    index = @directory |> Path.join("checksums.json") |> File.read!() |> Pulse.JSON.decode!()
    assert index["producer"]["otlp"] == "v1.11.0"
    assert index["producer"]["prometheus"] == "v0.315.0"
    assert map_size(index["files"]) == 6

    for {name, expected} <- index["files"] do
      bytes = File.read!(Path.join(@directory, name))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected, name
    end
  end

  test "randomized counts cannot leak mass past a rounded boundary" do
    :rand.seed(:exsss, {311, 902, 71})

    for _ <- 1..64 do
      counts = Enum.map(1..4, fn _ -> :rand.uniform(100) end)
      zero = :rand.uniform(100)
      count = Enum.sum(counts) + zero

      point =
        point(%{
          "scale" => 3,
          "count" => count,
          "zeroCount" => zero,
          "positive" => %{"offset" => -8595, "bucketCounts" => counts}
        })

      assert {:ok, rows, 0} = both(point)
      assert bucket_rows(rows) == [{"0", zero / 1}, {min_label(), count / 1}, {"+Inf", count / 1}]
    end
  end

  test "rounded subnormal boundaries coalesce their cumulative mass at the same boundary" do
    point = point(%{"scale" => 3, "count" => "10", "positive" => %{"offset" => -8595, "bucketCounts" => [1, 2, 3, 4]}})
    assert {:ok, samples, 0} = both(point)
    assert bucket_rows(samples) == [{"0", 0.0}, {min_label(), 10.0}, {"+Inf", 10.0}]
    assert hd(samples).otlp["point"]["positive"]["bucketCounts"] == ~w(1 2 3 4)
  end

  test "finite bounds above 2^1023 are not prematurely moved to infinity" do
    point = point(%{"scale" => 3, "count" => "1", "positive" => %{"offset" => 8187, "bucketCounts" => [1]}})
    assert {:ok, samples, 0} = both(point)
    assert [{"0", +0.0}, {upper, 1.0}, {"+Inf", 1.0}] = bucket_rows(samples)
    assert parse_bound(upper) > :math.pow(2.0, 1023)
  end

  test "negative infinite and rounded-zero bounds remain ordered and preserve totals" do
    point = point(%{"scale" => 0, "count" => "3", "negative" => %{"offset" => 1024, "bucketCounts" => [1, 2]}})
    assert {:ok, samples, 0} = both(point)
    assert bucket_rows(samples) == [{"-Inf", 3.0}, {"0", 3.0}, {"+Inf", 3.0}]

    point =
      point(%{
        "scale" => 3,
        "count" => "4",
        "zeroCount" => "1",
        "negative" => %{"offset" => -8604, "bucketCounts" => [1, 2]}
      })

    assert {:ok, samples, 0} = both(point)
    assert bucket_rows(samples) == [{"0", 4.0}, {"+Inf", 4.0}]
  end

  test "zero region contradictions reject while partial overlaps clip and stale values stay ignored" do
    bad =
      point(%{
        "scale" => 0,
        "count" => "1",
        "zeroThreshold" => 2.0,
        "positive" => %{"offset" => 0, "bucketCounts" => [1]}
      })

    assert {:ok, [], 1} = both(bad)
    assert {:ok, [], 1} = bad |> Map.delete("positive") |> Map.put("negative", bad["positive"]) |> both()

    partial =
      point(%{
        "scale" => 0,
        "count" => "3",
        "zeroCount" => "1",
        "zeroThreshold" => 1.5,
        "negative" => %{"offset" => 0, "bucketCounts" => [2]}
      })

    assert {:ok, samples, 0} = both(partial)
    assert bucket_rows(samples) == [{"-1.5", 2.0}, {"1.5", 3.0}, {"+Inf", 3.0}]
    assert {:ok, samples, 0} = both(Map.merge(bad, %{"flags" => 1, "count" => "0"}))
    assert Enum.all?(samples, &(&1.value == :stale))
    assert hd(samples).otlp["point"]["positive"]["bucketCounts"] == ["1"]
  end

  test "projected negative zero normalizes without changing the source threshold bits" do
    <<zero::float-64>> = <<0x8000000000000000::64>>
    assert {:ok, samples, 0} = both(point(%{"count" => "1", "zeroCount" => "1", "zeroThreshold" => zero}))
    assert bucket_rows(samples) == [{"0", 1.0}, {"+Inf", 1.0}]
    assert <<hd(samples).otlp["point"]["zeroThreshold"]::float-64>> == <<0x8000000000000000::64>>
  end

  test "raw and minimum-scale projected ceilings fail whole even with a valid scalar neighbor" do
    scalar = Fixture.gauge([Fixture.point()])
    raw = point(%{"count" => "0", "positive" => %{"bucketCounts" => List.duplicate(0, 65_537)}})
    wide = point(%{"scale" => -10, "count" => "161", "positive" => %{"bucketCounts" => List.duplicate(1, 161)}})

    for invalid <- [raw, wide] do
      payload = Fixture.payload([scalar, metric(invalid)])
      assert {:error, :too_many_records} = Metrics.decode(payload)
      assert {:error, :too_many_records} = Metrics.decode_protobuf(Fixture.protobuf(payload))
    end

    assert {:ok, rows, 0} =
             both(point(%{"scale" => -10, "count" => "160", "positive" => %{"bucketCounts" => List.duplicate(1, 160)}}))

    assert length(rows) <= 162
    Runtime.put_env(:pulse, Pulse.IngestLimits, max_records: 2)
    assert {:error, :too_many_records} = both(point(%{"count" => "0"}))
  end

  defp both(point) do
    payload = Fixture.payload([metric(point)])
    json = Metrics.decode(payload)
    assert bits(json) == bits(Metrics.decode_protobuf(Fixture.protobuf(payload)))
    json
  end

  defp metric(point),
    do: %{"name" => "boundary", "exponentialHistogram" => %{"aggregationTemporality" => 2, "dataPoints" => [point]}}

  defp point(fields), do: Map.merge(%{"timeUnixNano" => "1700000000123456789", "scale" => 0}, fields)
  defp bits(value), do: :erlang.term_to_binary(value, [:deterministic])

  defp bucket_rows(rows),
    do: rows |> Enum.filter(&Map.has_key?(&1.labels, "le")) |> Enum.map(&{&1.labels["le"], &1.value})

  defp min_label, do: "0." <> String.duplicate("0", 323) <> "5"
  defp parse_bound("+Inf"), do: :infinity
  defp parse_bound("-Inf"), do: :negative_infinity

  defp parse_bound(value) do
    case Float.parse(value) do
      {number, ""} -> number
    end
  end

  defp from_bits(hex) do
    case Base.decode16!(hex, case: :mixed) do
      <<0x7FF0000000000000::64>> -> :infinity
      <<0xFFF0000000000000::64>> -> :negative_infinity
      <<value::float-64>> -> value
    end
  end

  defp close?(a, b) when a == b, do: true
  defp close?(a, b) when is_float(a) and is_float(b), do: abs(a - b) <= abs(b) * 1.0e-14
  defp close?(_, _), do: false
end
