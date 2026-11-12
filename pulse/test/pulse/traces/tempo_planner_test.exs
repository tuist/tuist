defmodule Pulse.Traces.TempoPlannerTest do
  use Pulse.Test.Case, async: true

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.Record.Span
  alias Pulse.Storage.S3.TraceSummary
  alias Pulse.Traces.TempoSearch

  @query ~s'{resource.service.name="api"} with (most_recent=true)'

  test "proof requires rich original types, rejects duplicate keys, and never writes bad core headers" do
    row = row(1)
    assert {:ok, _, _, _, 1, true} = encode([row])
    assert {:ok, _, _, _, 1, false} = encode([%{row | otlp: nil}])
    assert {:ok, _, _, _, 1, false} = encode([%{row | service: "different"}])

    nonstring = %{
      row
      | service: "true",
        resource: %{"service.name" => "true"},
        otlp: %{row.otlp | "resource" => [%{"key" => "service.name", "value" => %{"boolValue" => true}}]}
    }

    assert {:ok, _, _, _, 1, true} = encode([nonstring])

    duplicate = %{
      row
      | otlp: %{
          row.otlp
          | "resource" => row.otlp["resource"] ++ [%{"key" => "service.name", "value" => %{"stringValue" => "other"}}]
        }
    }

    assert :fallback = encode([duplicate])

    for bad <- [%{row | span_id: String.duplicate("0", 16)}, %{row | kind: 6}, %{row | flags: -1}] do
      assert {:error, :trace_projection_invalid} = encode([bad])
    end

    assert {:ok, _, 0, 0, 0, true} = encode([])

    for services <- [nil, [], [String.duplicate("x", 257)], List.duplicate("x", 129)] do
      summary = TraceSummary.parse(%{"v" => 1, "k" => true, "s" => services})
      assert candidate?(summary)
    end

    wire = row |> List.wrap() |> TraceSummary.build(true) |> TraceSummary.to_wire()
    refute wire |> Map.delete("k") |> TraceSummary.parse() |> Map.fetch!(:pruning_safe?)
  end

  test "compaction reproves old rich sources without inventing metadata for legacy" do
    assert {:ok, rich, _, _, _, true} = encode([row(1)])
    assert {:ok, old, _, _, _, false} = encode([%{row(2) | otlp: nil}])
    assert {:ok, _, _, _, 2, {_, _, true}} = NIF.compact_trace_segments_v2([rich, rich], 10)
    assert {:ok, _, _, _, 2, {_, _, false}} = NIF.compact_trace_segments_v2([rich, old], 10)
  end

  test "native prefix/canonical bit order agrees with independent Elixir probes and malformed hints add reads" do
    candidates = Enum.map([1, 17, 257, 65_535], &hex/1)
    state = planned(Enum.map([1, 17, 257, 65_535], &row/1))

    for size <- [1, 32, 256, 257, 1000], include? <- [false, true] do
      ids = Enum.map(2000..(1999 + size), &hex/1)
      ids = if include?, do: [hex(17) | ids], else: ids
      summary = TraceSummary.from_values(["noise"], ids, true)
      {hashes, bits} = TraceSummary.context_filter(summary)
      expected = reference_match(summary, candidates)
      assert {:ok, ^expected} = NIF.tempo_search_plan_may_match(state, hashes, bits)
    end

    for {hashes, bits} <- [{nil, nil}, {<<1>>, nil}, {nil, <<1>>}, {nil, :binary.copy(<<0>>, 2048)}] do
      assert {:ok, true} = NIF.tempo_search_plan_may_match(state, hashes, bits)
    end

    assert NIF.tempo_search_abort(state)
  end

  @tag timeout: 120_000
  test "two million native index probes fall back to reads instead of truncating context" do
    state = planned(Enum.map(1..10_000, &row/1))
    bits = canonical_for(hex(20_001))
    for _ <- 1..200, do: assert({:ok, false} = NIF.tempo_search_plan_may_match(state, nil, bits))
    assert {:ok, true} = NIF.tempo_search_plan_may_match(state, nil, bits)
    assert {:ok, true} = NIF.tempo_search_plan_may_match(state, <<0::64>>, nil)
    assert NIF.tempo_search_abort(state)
  end

  test "a new potential match after seal poisons rather than expanding or clipping candidates" do
    state = planned([row(1)])
    {:ok, blob, _, _, _, _} = encode([row(2)])
    assert :fallback = NIF.tempo_search_add(state, blob)
    assert :fallback = NIF.tempo_search_finish(state)
  end

  test "layout permutations and coalescing preserve the unplanned complete-context answer" do
    rows =
      for trace <- 1..12, slot <- 0..2 do
        service =
          case slot do
            0 -> "edge"
            1 -> if rem(trace, 2) == 0, do: "api", else: "noise"
            2 -> "worker"
          end

        base = row(trace, service)

        %{
          base
          | span_id: Base.encode16(<<slot + 1::64>>, case: :lower),
            parent_span_id: if(slot != 0, do: Base.encode16(<<1::64>>, case: :lower)),
            timestamp_ns: trace * 10 + slot,
            end_timestamp_ns: trace * 10 + slot + 1
        }
      end

    {:ok, predicates} = TempoSearch.parse(@query)
    {:ok, expected} = TempoSearch.json(rows, predicates, trace_start: 1, trace_end: 1000, spss: 1)

    for partitions <- [1, 2, 5, 17], reverse? <- [false, true] do
      batches =
        rows
        |> Enum.group_by(&:erlang.phash2({&1.trace_id, &1.span_id}, partitions))
        |> Enum.sort()
        |> Enum.map(&elem(&1, 1))

      batches = if reverse?, do: Enum.reverse(batches), else: batches
      assert {:ok, json} = execute_plan(batches)
      assert Pulse.JSON.decode!(json) == Pulse.JSON.decode!(expected)
    end
  end

  defp row(id, service \\ "api") do
    %Span{
      timestamp_ns: 1,
      end_timestamp_ns: 2,
      trace_id: hex(id),
      span_id: Base.encode16(<<1::64>>, case: :lower),
      service: service,
      resource: %{"service.name" => service},
      otlp: %{
        "version" => 1,
        "resource" => [%{"key" => "service.name", "value" => %{"stringValue" => service}}],
        "scope" => [],
        "attributes" => [],
        "events" => [],
        "links" => []
      }
    }
  end

  defp hex(id), do: Base.encode16(<<id::128>>, case: :lower)

  defp candidate?(summary) do
    {:ok, predicates} = TempoSearch.parse(@query)
    TraceSummary.matches?(summary, TraceSummary.tempo_filters(predicates))
  end

  defp encode(rows), do: NIF.encode_trace_segment_parquet_v2(Enum.map(rows, &Span.to_map/1))

  defp new_state do
    {:ok, predicates} = TempoSearch.parse(@query)
    {:ok, state} = NIF.tempo_search_new(0, 1, 1000, predicates, 100, 1)
    state
  end

  defp planned(rows) do
    state = new_state()
    {:ok, blob, _, _, _, _} = encode(rows)
    assert {:ok, _} = NIF.tempo_search_add(state, blob)
    seal(state)
    state
  end

  defp seal(state) do
    assert {:ok, ids} = NIF.tempo_search_plan_seal(state)
    hashes = for <<id::binary-size(32) <- ids>>, into: <<>>, do: :binary.part(:crypto.hash(:sha256, id), 0, 8)
    assert {:ok, true} = NIF.tempo_search_plan_hashes(state, hashes)
  end

  defp reference_match(%{lookup_hashes: hashes}, candidates) when is_binary(hashes) do
    known = MapSet.new(for <<prefix::binary-size(8) <- hashes>>, do: prefix)
    Enum.any?(candidates, &MapSet.member?(known, :binary.part(:crypto.hash(:sha256, &1), 0, 8)))
  end

  defp reference_match(summary, candidates), do: Enum.any?(candidates, &TraceSummary.matches?(summary, trace_id: &1))

  defp canonical_for(id) do
    <<hash::64, _::binary>> = :crypto.hash(:sha256, id)
    a = bsr(hash, 32)
    b = bor(band(hash, 0xFFFF_FFFF), 1)
    bits = Enum.reduce(0..3, 0, &bor(&2, bsl(1, rem(a + &1 * b, 16_384))))
    <<bits::unsigned-size(16_384)>>
  end

  defp execute_plan(batches) do
    sources =
      Enum.map(batches, fn rows ->
        {:ok, blob, _, _, _, proof} = encode(rows)
        {blob, TraceSummary.build(rows, proof)}
      end)

    {first, remaining} =
      Enum.split_with(sources, fn {_blob, summary} -> candidate?(summary) end)

    state = new_state()
    Enum.each(first, fn {blob, _} -> assert {:ok, _} = NIF.tempo_search_add(state, blob) end)
    seal(state)
    Enum.each(remaining, fn {blob, summary} -> add_context(state, blob, summary) end)
    NIF.tempo_search_finish(state)
  end

  defp add_context(state, blob, summary) do
    {hashes, bits} = TraceSummary.context_filter(summary)
    assert {:ok, match?} = NIF.tempo_search_plan_may_match(state, hashes, bits)
    if match?, do: assert({:ok, _} = NIF.tempo_search_add(state, blob))
  end
end
