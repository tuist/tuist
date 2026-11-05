defmodule Pulse.Traces.TempoRootsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Test.PreRootDiscoveryStorage
  alias Pulse.Traces.{TempoDiscovery, TempoRootDiscovery}

  @fixture "test/fixtures/traces/"
  @keys ~w(rootName trace:rootName rootServiceName trace:rootService)
  setup do
    {:ok, rows, 0} = (@fixture <> "tempo-roots-input.protobuf") |> File.read!() |> Traces.decode_protobuf()
    %{rows: rows, cases: Pulse.JSON.decode!(File.read!(@fixture <> "tempo-roots-oracle.json"))}
  end

  # 44 oracle cases each run the reference and five native segment layouts,
  # whose dirty-CPU NIF calls queue behind other tests' native work under CI
  # contention. Keep every comparison without the ordinary one-minute budget.
  @tag timeout: 300_000
  test "pinned actual engine selections, raw dictionaries and complete root results", %{rows: rows, cases: cases} do
    for {file, hash} <- [
          {"tempo-roots-input.protobuf", "ae50a9bc5b06df9eb7e3fde68dae7b2f689ef1898e2f8f70712570b354598706"},
          {"tempo-roots-oracle.json", "179753f73b0f3151e7d4320ae9ceb2a058eceb1bb1cecfab33c77b6fea9b3edf"},
          {"produce_tempo_roots.go.txt", "a569af4d9ad7046b59a6994d4a79e8c4b5432440c16dc124c556270fc01d8783"}
        ],
        do: assert(Base.encode16(:crypto.hash(:sha256, File.read!(@fixture <> file)), case: :lower) == hash)

    assert length(cases) == 44
    successes = Enum.reject(cases, &Map.has_key?(&1, "expected_error"))
    assert length(successes) == 22
    assert Enum.all?(successes, &(&1["raw"] == &1["complete"]))

    for c <- cases do
      opts = [discovery_query: c["query"]]
      expected = expected(c)
      assert decoded(TempoRootDiscovery.json(rows, c["target"], opts)) == expected

      for segments <- [[rows], [Enum.reverse(rows)], Enum.map(rows, &[&1]), [rows, rows]] do
        assert decoded(native(segments, c["target"], opts)) == expected
      end
    end
  end

  test "windowed parents recover roots outside source envelopes and filters", %{rows: rows} do
    [root, child | _] = rows
    child = %{child | timestamp_ns: 2_000_000_000, end_timestamp_ns: 2_000_000_001}
    parts = [[root], [child]]
    opts = [discovery_window: {2_000_000_000, 2_000_000_000}, discovery_query: ~s({resource.service.name="worker"})]

    for key <- @keys do
      assert decoded(native(parts, key, opts)) == decoded(TempoRootDiscovery.segments_json(parts, key, opts))
      wanted = if key in ~w(rootName trace:rootName), do: "GET /api", else: "gateway"

      assert decoded(native(Enum.reverse(parts), key, opts)) ==
               {:ok, %{"tagValues" => [%{"type" => "string", "value" => wanted}]}}
    end

    assert TempoRootDiscovery.json([root, child], "rootName", opts) == {:error, :unsupported_trace_discovery}
    assert native(parts, "rootName", opts, root.end_timestamp_ns + 1) == {:error, :trace_root_unknown}

    assert TempoRootDiscovery.segments_json(
             parts,
             "rootName",
             Keyword.put(opts, :discovery_floor, root.end_timestamp_ns + 1)
           ) == {:error, :trace_root_unknown}

    assert native(parts, "rootName", Keyword.put(opts, :discovery_window, {3_000_000_000, 3_000_000_000})) |> decoded() ==
             {:ok, %{"tagValues" => []}}
  end

  test "legacy context and corrupt nonmatches fail, unrelated excluded metadata is not guessed", %{
    rows: [root, child | _]
  } do
    legacy = %{root | otlp: nil}
    q = [discovery_query: ~s({resource.service.name="absent"})]
    assert native([[legacy, child]], "rootName", q) == {:error, :trace_metadata_unknown}
    assert TempoRootDiscovery.json([legacy, child], "rootName", q) == {:error, :trace_metadata_unknown}
    assert native([[File.read!(@fixture <> "trace-invalid-version.parquet")]], "rootName", q) == :fallback
    assert {:error, _} = TempoRootDiscovery.json([%{root | kind: 999}], "rootName", q)
    child = %{child | timestamp_ns: 2_000_000_000, end_timestamp_ns: 2_000_000_001}
    opts = [discovery_window: {2_000_000_000, 2_000_000_000}, discovery_query: ~s({resource.service.name="worker"})]
    assert native([[legacy], [child]], "rootName", opts) == {:error, :trace_metadata_unknown}
    unrelated = %{legacy | trace_id: String.duplicate("e", 32)}

    assert decoded(native([[root], [child], [unrelated]], "rootName", opts)) ==
             {:ok, %{"tagValues" => [%{"type" => "string", "value" => "GET /api"}]}}
  end

  @tag timeout: 120_000
  test "requested evidence work precedes filters, repeated owners count, dictionaries never truncate", %{
    rows: [root | _]
  } do
    attrs = for n <- 1..1000, do: %{"key" => "k#{n}", "value" => %{"stringValue" => "x"}}

    dense = %{
      root
      | service: nil,
        resource: %{},
        attributes: %{},
        links: [
          %{
            "trace_id" => String.duplicate("f", 32),
            "span_id" => String.duplicate("f", 16),
            "attributes" => Map.new(attrs, &{&1["key"], "x"})
          }
        ],
        otlp: %{root.otlp | "resource" => attrs, "attributes" => attrs, "links" => [attrs]}
    }

    # 2 owners + 2000 attrs + 1 link + its 1000 attrs = 3003.
    opts = [discovery_query: ~s({span.absent="no"})]

    assert decoded(native(Enum.chunk_every(List.duplicate(dense, 666), 32), "rootName", opts)) ==
             {:ok, %{"tagValues" => []}}

    assert native(Enum.chunk_every(List.duplicate(dense, 667), 32), "rootName", opts) ==
             {:error, :trace_discovery_work_limit}

    assert TempoRootDiscovery.json(List.duplicate(dense, 667), "rootName", opts) ==
             {:error, :trace_discovery_work_limit}

    source = blob([dense])
    copies = div(33_554_432, byte_size(source)) + 1
    assert copies <= 666
    assert native(List.duplicate([source], copies), "rootName", opts) == {:error, :query_resource_limit}

    many = for n <- 1..5001, do: %{root | trace_id: hex(n, 32), name: "root#{n}"}
    boundary = Enum.take(many, 5000)
    assert {:ok, %{"tagValues" => values}} = complete = decoded(native([boundary], "rootName", []))
    assert length(values) == 5000
    assert decoded(TempoRootDiscovery.json(boundary, "rootName", [])) == complete
    assert native([many], "rootName", []) == {:error, :query_resource_limit}
    assert TempoRootDiscovery.json(many, "rootName", []) == {:error, :query_resource_limit}

    escaped =
      for n <- 1..700, do: %{root | trace_id: hex(n, 32), name: String.duplicate("\"", 1000) <> Integer.to_string(n)}

    assert native([escaped], "rootName", []) == {:error, :query_resource_limit}
    assert TempoRootDiscovery.json(escaped, "rootName", []) == {:error, :query_resource_limit}
    # Exercise every source admission without re-encoding the same fixture.
    assert native(List.duplicate([blob([root])], 1025), "rootName", []) == {:error, :query_resource_limit}
  end

  test "closed target grammar and callback fences never dispatch roots to span-local adapters", %{rows: rows} do
    assert :ok = Storage.append(:traces, "roots", rows)
    Pulse.Runtime.put_env(:pulse, Storage, adapter: PreRootDiscoveryStorage)
    opts = [discovery_query: ~s({span.case="normal"})]
    assert {:ok, _} = Storage.tempo_discovery_json("roots", "intrinsic", "rootName", opts)

    assert Storage.tempo_discovery_json("roots", "intrinsic", "rootName", Keyword.put(opts, :max_scan_rows, 1)) ==
             {:error, :query_scan_limit}

    assert {:error, :query_sample_limit} = Storage.Memory.query(:traces, "roots", max_records: 1)
    assert {:ok, all} = Storage.Memory.query(:traces, "roots", max_records: length(rows))
    assert length(all) == length(rows)

    assert Storage.tempo_discovery_json(
             "roots",
             "intrinsic",
             "rootName",
             Keyword.put(opts, :discovery_window, {1, 10_000_000_000})
           ) == {:error, :unsupported_trace_discovery}

    assert {:error, :unsupported_trace_discovery} =
             TempoDiscovery.filter("intrinsic", "rootName", ~s({trace:rootName="GET /api"}))

    assert {:error, :unsupported_trace_discovery} = TempoDiscovery.filter("intrinsic", "rootName", ~s({span.case=2}))

    for key <- ["root.name", "root.service.name"],
        do: assert(TempoDiscovery.validate("none", key) == {:error, :unsupported_trace_discovery})
  end

  defp expected(%{"expected_error" => "trace_root_conflict"}), do: {:error, :trace_root_conflict}
  defp expected(%{"expected_error" => "trace_root_unknown"}), do: {:error, :trace_root_unknown}
  defp expected(c), do: {:ok, c["complete"]}
  defp decoded({:ok, body}), do: {:ok, Pulse.JSON.decode!(body)}
  defp decoded(error), do: error
  defp hex(n, width), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")

  defp blob([blob]) when is_binary(blob), do: blob

  defp blob(rows) do
    {:ok, blob, _, _} = Storage.S3.encode_segment(:traces, rows)
    blob
  end

  defp add(state, rows, :ok) do
    case NIF.tempo_search_add(state, blob(rows)) do
      {:ok, _} -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp native(parts, key, opts, floor \\ 0) do
    {:ok, predicates} = TempoDiscovery.filter("intrinsic", key, opts[:discovery_query])
    {start, finish} = opts[:discovery_window] || {0, 0}
    {:ok, state} = NIF.tempo_root_discovery_new(floor, key, predicates, start, finish)

    case Enum.reduce_while(parts, :ok, &add(state, &1, &2)) do
      :ok -> NIF.tempo_root_discovery_finish(state)
      error -> error
    end
  end
end
