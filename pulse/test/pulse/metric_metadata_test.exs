defmodule Pulse.MetricMetadataTest do
  use Pulse.Test.Case, async: true

  alias Pulse.MetricMetadata

  @today 20_000

  test "keeps every reported variant, most recently reported first" do
    set =
      %{}
      |> MetricMetadata.merge([{"up", "gauge", "Target up.", ""}], @today - 2)
      |> MetricMetadata.merge(
        [{"up", "gauge", "Is the target up.", ""}, {"rq_total", "counter", "Requests.", ""}],
        @today
      )

    assert MetricMetadata.view(set, @today, []) == %{
             "rq_total" => [%{"type" => "counter", "help" => "Requests.", "unit" => ""}],
             "up" => [
               %{"type" => "gauge", "help" => "Is the target up.", "unit" => ""},
               %{"type" => "gauge", "help" => "Target up.", "unit" => ""}
             ]
           }

    assert MetricMetadata.view(set, @today, metric: "up", limit_per_metric: 1) == %{
             "up" => [%{"type" => "gauge", "help" => "Is the target up.", "unit" => ""}]
           }

    assert map_size(MetricMetadata.view(set, @today, limit: 1)) == 1
    assert MetricMetadata.view(set, @today, limit: -1) |> map_size() == 2
  end

  test "reports whether a merge changes the set, so unchanged pushes write nothing" do
    set = MetricMetadata.merge(%{}, [{"up", "gauge", "h", ""}], @today)
    refute MetricMetadata.changed?(set, [{"up", "gauge", "h", ""}], @today)
    assert MetricMetadata.changed?(set, [{"up", "gauge", "h", ""}], @today + 1)
    assert MetricMetadata.changed?(set, [{"up", "counter", "h", ""}], @today)
  end

  test "expires variants unreported for 30 days and bounds variants per metric" do
    old = MetricMetadata.merge(%{}, [{"old", "gauge", "", ""}], @today - 30)
    assert MetricMetadata.view(old, @today, []) == %{}
    assert MetricMetadata.merge(old, [{"new", "gauge", "", ""}], @today) |> Map.keys() == ["new"]

    many = for i <- 1..10, do: {"m", "gauge", "help #{i}", ""}

    bounded =
      Enum.with_index(many) |> Enum.reduce(%{}, fn {e, i}, acc -> MetricMetadata.merge(acc, [e], @today - 10 + i) end)

    assert map_size(bounded["m"]) == 8
    refute Map.has_key?(bounded["m"], {"gauge", "help 1", ""})
  end

  test "byte eviction keeps the newest suffix and counts escaped UTF-8 JSON exactly" do
    help = String.duplicate("\"\\\nµ", 500)

    old =
      Map.new(1..2_500, fn i ->
        {"old_#{String.pad_leading(Integer.to_string(i), 4, "0")}", %{{"gauge", help, "s"} => @today - 1}}
      end)

    entries = for i <- 1..1_000, do: {"new_#{i}", "counter", String.duplicate("x", 3000), "s"}
    bounded = MetricMetadata.merge(old, entries, @today)
    assert byte_size(MetricMetadata.encode(bounded)) <= MetricMetadata.max_bytes()
    assert Enum.all?(entries, fn {metric, _, _, _} -> Map.has_key?(bounded, metric) end)

    kept_old = bounded |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "old_")) |> Enum.sort()
    all_old = old |> Map.keys() |> Enum.sort()
    assert kept_old != [] and length(kept_old) < length(all_old)
    assert kept_old == Enum.take(all_old, -length(kept_old))

    # Removing the next-oldest remaining boundary must be necessary, not a
    # conservative estimate that silently evicts extra variants.
    last_dropped = Enum.at(all_old, length(all_old) - length(kept_old) - 1)
    with_next = Map.put(bounded, last_dropped, Map.fetch!(old, last_dropped))
    assert byte_size(MetricMetadata.encode(with_next)) > MetricMetadata.max_bytes()
    assert {:ok, ^bounded} = bounded |> MetricMetadata.encode() |> MetricMetadata.decode()
  end

  test "round-trips its stored form and rejects anything else" do
    set = MetricMetadata.merge(%{}, [{"up", "gauge", String.duplicate("h", 200), "s"}], @today)
    assert {:ok, ^set} = set |> MetricMetadata.encode() |> MetricMetadata.decode()
    assert {:error, :invalid_metric_metadata} = MetricMetadata.decode(~s({"v":2,"m":{}}))
    assert {:error, :invalid_metric_metadata} = MetricMetadata.decode(~s({"v":1,"m":{"up":[["gauge"]]}}))
  end
end
