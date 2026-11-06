defmodule Pulse.Traces.TempoWindowedDiscoveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.{Codec.NIF, OTLP.Traces, Runtime, Storage}
  alias Pulse.Storage.S3
  alias Pulse.Traces.{TempoDiscovery, TempoSearch}

  defp rows do
    {:ok, [a, b | _], 0} =
      Traces.decode_protobuf(
        File.read!(Path.expand("../../fixtures/traces/tempo-windowed-discovery-input.protobuf", __DIR__))
      )

    [
      %{a | name: "early", timestamp_ns: 10_000_000_000, end_timestamp_ns: 11_000_000_000},
      %{b | name: "late", timestamp_ns: 20_000_000_000, end_timestamp_ns: 21_000_000_000}
    ]
  end

  defp native(segments, window, floor \\ 0, scope \\ "intrinsic", key \\ "name", query \\ nil) do
    {:ok, predicates} = TempoDiscovery.filter(scope, key, query)
    {:ok, state} = NIF.tempo_windowed_discovery_new(floor, scope, key, predicates, elem(window, 0), elem(window, 1))

    result =
      Enum.reduce_while(segments, :ok, fn rows, _ ->
        {:ok, blob, _, _} = S3.encode_segment(:traces, rows)

        case NIF.tempo_discovery_add(state, blob) do
          {:ok, count} ->
            assert count == length(rows)
            {:cont, :ok}

          error ->
            {:halt, error}
        end
      end)

    if result == :ok, do: NIF.tempo_discovery_finish(state), else: result
  end

  defp names(json), do: Enum.map(Pulse.JSON.decode!(json)["tagValues"], &Map.get(&1, "value", ""))

  test "independent actual frontend routing and public Parquet dictionaries compose the five window cases" do
    dir = Path.expand("../../fixtures/traces", __DIR__)

    for {file, hash} <- [
          {"tempo-windowed-discovery-input.protobuf",
           "da102fd775b53baca6f069a841bcba89e8c25911d0761832c34e93ba2cbb151f"},
          {"tempo-windowed-discovery-oracle.json", "f1071cade0054b90976f6bdee652dd3939205357d9ae18ddbc035213f87b9e2c"},
          {"produce_tempo_windowed_discovery.go.txt",
           "4d20efeabdc8c866084cc316badf7ba20ed229d3a0a2c0a6ea640f9281789a7a"},
          {"tempo-time-routing-oracle.json", "938eef01325b616dd721c8e67f3dd3f216f9a337511a7479fc131fa3ff77c0ad"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(dir, file))), case: :lower) == hash
    end

    cases = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-windowed-discovery-oracle.json")))
    assert length(cases) == 5

    for c <- cases do
      assert {:ok, json} = native([rows()], {c["start"] * 1_000_000_000, c["end"] * 1_000_000_000})
      assert Pulse.JSON.decode!(json) == %{"tagValues" => Map.get(c["response"], "tagValues", [])}
    end
  end

  test "actual distributor second truncation and frontend metadata routing establish the HTTP subsecond upper edge" do
    dir = Path.expand("../../fixtures/traces", __DIR__)

    for {file, hash} <- [
          {"tempo-windowed-subsecond-input.protobuf",
           "f11ec3ed00c2393ea4aff2e8584651eefab92865a9bf6c45cb80032edde75e15"},
          {"tempo-windowed-subsecond-oracle.json", "e10dade7668b5014135258b9585870e56e8c7bdd46bc0dc49e689511dfd06bc1"},
          {"tempo-subsecond-routing-oracle.json", "88cd706e2880b5c8523c5446062099a397dd2f030501ec81cef7ea5bcfdacc33"},
          {"tempo-span-time-oracle.json", "11d5eace551faabb794a7461bf739e14e362715fd346f54886948cd906eee29f"},
          {"produce_tempo_span_time.go.txt", "a5bb0b5e5e1d8ca281a7a0fb83c98a653c7458afc2278534925fdf2806a9e788"},
          {"produce_tempo_subsecond_routing.go.txt",
           "7d8dbc2f27c540f6cdf63245df43fdd1089da1d248ad5f9337b54a71beffc462"},
          {"produce_tempo_windowed_subsecond.go.txt",
           "765317e1cc6f6bf0a03072751186ccc2c3637a28f7812c5c013ad8955eb36812"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(dir, file))), case: :lower) == hash
    end

    {:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(dir, "tempo-windowed-subsecond-input.protobuf")))
    cases = Pulse.JSON.decode!(File.read!(Path.join(dir, "tempo-windowed-subsecond-oracle.json")))

    for c <- cases do
      assert {:ok, json} = native([rows], {c["start"] * 1_000_000_000, c["end"] * 1_000_000_000 + 999_999_999})
      assert Pulse.JSON.decode!(json) == %{"tagValues" => Map.get(c["response"], "tagValues", [])}
    end

    assert {:ok, json} = native([rows], {20_000_000_000, 20_000_000_000})
    assert names(json) == []
    assert {:ok, json} = native([rows], {20_000_000_000, 20_999_999_999})
    assert names(json) == ["fractional"]
  end

  test "inclusive segment envelopes include gaps and outside-window parents, not point-time filtering" do
    [a, b] = rows()

    for {start, finish, expected} <- [
          {9, 9, []},
          {9, 10, ["early", "late"]},
          {15, 16, ["early", "late"]},
          {21, 21, ["early", "late"]},
          {22, 23, []}
        ] do
      window = {start * 1_000_000_000, finish * 1_000_000_000}

      for segments <- [[[a, b]], [[b, a]], [[a, b], [a, b]]] do
        assert {:ok, json} = native(segments, window)
        assert names(json) == expected
        assert TempoDiscovery.segments_json(segments, "intrinsic", "name", discovery_window: window) == {:ok, json}
      end
    end

    assert {:ok, json} = native([[a], [b]], {15_000_000_000, 16_000_000_000})
    assert names(json) == []
    assert {:ok, json} = native([[a], [b]], {20_000_000_000, 20_000_000_000})
    assert names(json) == ["late"]
  end

  test "retention reshapes the visible envelope and legacy uncertainty is local to selected segments" do
    [a, b] = rows()
    legacy = %{a | otlp: nil}
    assert {:ok, json} = native([[legacy], [b]], {20_000_000_000, 20_000_000_000})
    assert names(json) == ["late"]
    assert {:error, :trace_metadata_unknown} = native([[legacy, b]], {15_000_000_000, 16_000_000_000})
    assert {:ok, json} = native([[legacy, b]], {15_000_000_000, 16_000_000_000}, 15_000_000_000)
    assert names(json) == []
    assert {:ok, json} = native([[legacy, b]], {20_000_000_000, 20_000_000_000}, 15_000_000_000)
    assert names(json) == ["late"]

    assert TempoDiscovery.segments_json([[legacy, b]], "intrinsic", "name",
             discovery_window: {20_000_000_000, 20_000_000_000},
             discovery_floor: 15_000_000_000
           ) == {:ok, json}

    long = %{a | end_timestamp_ns: 100_000_000_000}
    assert {:ok, json} = native([[long]], {90_000_000_000, 91_000_000_000})
    assert names(json) == ["early"]
  end

  test "all scoped, combined, unscoped and filtered contracts use the selected context, static suggestions survive emptiness" do
    segments = [rows()]

    for {scope, key, q} <- [
          {"none", "", nil},
          {"resource", "", nil},
          {"span", "", ~s'{resource.service.name="absent"}'},
          {"none", "service.name", nil},
          {"event", "f", nil},
          {"intrinsic", "name", ~s'{resource.service.name="early-service"}'}
        ] do
      for window <- [{15_000_000_000, 16_000_000_000}, {22_000_000_000, 23_000_000_000}] do
        assert {:ok, json} = native(segments, window, 0, scope, key, q)

        assert TempoDiscovery.segments_json(segments, scope, key, discovery_window: window, discovery_query: q) ==
                 {:ok, json}
      end
    end
  end

  test "window-aware callbacks never silently fall back to flat adapters; static vocabulary stays independent" do
    Runtime.put_env(:pulse, TempoSearch, enabled: true)

    for window <- [{nil, 2}, {2, 1}, {0, 1}, {1, 9_223_372_036_854_775_808}, "1"] do
      assert {:error, :unsupported_trace_discovery} =
               TempoDiscovery.query("window", "intrinsic", "kind", 2, "json", nil, window)

      assert {:error, :unsupported_trace_discovery} =
               Storage.tempo_discovery_json("window", "span", "x", discovery_window: window)
    end

    assert {:error, :unsupported_trace_discovery} =
             TempoDiscovery.query("window", "intrinsic", "name", 2, "json", nil, {1, 2})

    assert {:error, :unsupported_trace_discovery} = TempoDiscovery.json(rows(), "span", "f", discovery_window: {1, 2})
    assert {:ok, json} = TempoDiscovery.query("window", "intrinsic", "kind", 2, "json", nil, {1, 2})
    assert length(Pulse.JSON.decode!(json)["tagValues"]) == 6
  end

  test "unselected raw rows still exhaust the native scan bound and poison state" do
    [a | _] = rows()
    {:ok, blob, _, _} = S3.encode_segment(:traces, List.duplicate(%{a | otlp: nil}, 10_000))
    {:ok, state} = NIF.tempo_windowed_discovery_new(0, "intrinsic", "name", [], 1, 1)
    for _ <- 1..100, do: assert({:ok, 10_000} == NIF.tempo_discovery_add(state, blob))
    assert {:error, :query_scan_limit} = NIF.tempo_discovery_add(state, blob)
    assert :fallback = NIF.tempo_discovery_finish(state)
  end
end
