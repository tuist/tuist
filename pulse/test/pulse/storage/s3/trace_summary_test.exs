defmodule Pulse.Storage.S3.TraceSummaryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Storage.S3.TraceSummary
  alias Pulse.Traces.TempoSearch

  test "adaptive bounded bloom survives wire round trips with no false negatives" do
    records =
      for n <- 1..2000, do: %{trace_id: Base.encode16(<<n::128>>, case: :lower), service: "service-#{rem(n, 5)}"}

    summary = TraceSummary.build(records)
    assert summary.bits == nil
    assert byte_size(summary.lookup_bits) == 2048
    assert TraceSummary.parse(TraceSummary.to_wire(summary)) == summary

    for record <- records do
      assert TraceSummary.matches?(summary, trace_id: record.trace_id, service: record.service)
    end

    refute TraceSummary.matches?(summary, service: "missing")
    small = TraceSummary.build(Enum.take(records, 1))
    assert byte_size(small.bits) == 16
    refute TraceSummary.matches?(small, trace_id: String.duplicate("f", 32))
  end

  test "leaf summaries preserve complete unions across differently sized segment blooms" do
    records = for n <- 1..2000, do: %{trace_id: Base.encode16(<<n::128>>, case: :lower), service: "api"}
    entries = for batch <- Enum.chunk_every(records, 137), do: %{"t" => TraceSummary.to_wire(TraceSummary.build(batch))}
    summary = TraceSummary.page_summary(entries)
    for record <- records, do: assert(TraceSummary.page_matches?(summary, trace_id: record.trace_id, service: "api"))
    refute TraceSummary.page_matches?(summary, service: "absent")
    legacy = Enum.map(entries, &update_in(&1["t"], fn t -> Map.delete(t, "h") end))
    unknown = TraceSummary.page_summary(legacy)
    assert unknown["b"] == nil
    assert TraceSummary.page_matches?(unknown, trace_id: String.duplicate("f", 32))
    large = TraceSummary.build(records)
    assert large.lookup_hashes == nil
    canonical = TraceSummary.page_summary([%{"t" => TraceSummary.to_wire(large)} | Enum.take(entries, 1)])
    assert byte_size(Base.decode64!(canonical["b"])) == 2048
    for record <- records, do: assert(TraceSummary.page_matches?(canonical, trace_id: record.trace_id))

    # An old reader only sees unknown b/h, never an incomplete set.
    old = large |> TraceSummary.to_wire() |> Map.delete("c") |> TraceSummary.parse()
    assert TraceSummary.matches?(old, trace_id: String.duplicate("f", 32))
    assert TraceSummary.page_summary([%{"t" => TraceSummary.to_wire(old)}])["b"] == nil

    for wire <- [nil, %{"v" => 9}, %{"v" => 1, "b" => "corrupt"}],
        do: assert(TraceSummary.page_matches?(wire, trace_id: String.duplicate("f", 32)))
  end

  test "canonical geometry is versioned and unknown entries prevent leaf ID pruning" do
    records = for n <- 1..5000, do: %{trace_id: Base.encode16(<<n::128>>, case: :lower), service: "api"}
    summary = TraceSummary.build(records)
    assert TraceSummary.from_values(["api"], Enum.map(records, & &1.trace_id)) == summary
    assert TraceSummary.parse(TraceSummary.to_wire(summary)) == summary
    leaf = TraceSummary.page_summary([%{"t" => TraceSummary.to_wire(summary)}])

    for record <- records do
      assert TraceSummary.matches?(summary, trace_id: record.trace_id)
      assert TraceSummary.page_matches?(leaf, trace_id: record.trace_id)
    end

    for c <- [
          nil,
          %{"v" => 2, "b" => Base.encode64(summary.lookup_bits)},
          %{"v" => 1, "b" => Base.encode64(:binary.copy(<<255>>, 1024))},
          %{"v" => 1, "b" => Base.encode64(:binary.copy(<<0>>, 2048))},
          %{"v" => 1, "b" => "bad"}
        ] do
      wire = Map.put(TraceSummary.to_wire(summary), "c", c)
      assert TraceSummary.parse(wire).lookup_bits == nil
      assert TraceSummary.matches?(TraceSummary.parse(wire), trace_id: String.duplicate("f", 32))
      assert TraceSummary.page_summary([%{"t" => wire}, %{"t" => TraceSummary.to_wire(summary)}])["b"] == nil
    end
  end

  test "unknown versions, malformed/absent fields and legacy summaries cannot exclude data" do
    for wire <- [
          nil,
          %{},
          %{"v" => 2},
          %{"v" => 1, "s" => [], "b" => "not-base64"},
          %{"v" => 1, "b" => Base.encode64("short")},
          %{"v" => 1, "b" => Base.encode64(:binary.copy(<<0>>, 16))}
        ] do
      assert TraceSummary.matches?(TraceSummary.parse(wire), trace_id: String.duplicate("f", 32), service: "unknown")
    end

    summary = TraceSummary.build([%{trace_id: "bad", service: nil}])
    assert TraceSummary.matches?(summary, trace_id: String.duplicate("f", 32), service: "unknown")
    records = for n <- 1..129, do: %{trace_id: Base.encode16(<<n::128>>, case: :lower), service: "s#{n}"}
    assert TraceSummary.build(records).services == nil
  end

  test "proven page service sets prune resource service.name filters, unproven ones never do" do
    proven = for service <- ["kura-cache-0", "api"], do: TraceSummary.build([%{trace_id: nil, service: service}], true)
    page = TraceSummary.page_summary(Enum.map(proven, &%{"t" => TraceSummary.to_wire(&1)}))
    assert page["k"] == true

    assert TraceSummary.page_matches?(page, resource_regex: %{"service.name" => "kura-.*"})
    refute TraceSummary.page_matches?(page, resource_regex: %{"service.name" => "kura-meta.*"})
    assert TraceSummary.page_matches?(page, resource: %{"service.name" => "api"})
    refute TraceSummary.page_matches?(page, resource: %{"service.name" => "web"})
    # Both filters must hold for the same service.
    refute TraceSummary.page_matches?(page,
             resource: %{"service.name" => "api"},
             resource_regex: %{"service.name" => "kura.*"}
           )

    assert TraceSummary.page_matches?(page, resource_regex: %{"service.namespace" => "nothing"})

    unproven = [TraceSummary.build([%{trace_id: nil, service: "api"}]) | proven]
    page = TraceSummary.page_summary(Enum.map(unproven, &%{"t" => TraceSummary.to_wire(&1)}))
    refute Map.has_key?(page, "k")
    assert TraceSummary.page_matches?(page, resource: %{"service.name" => "web"})
    refute TraceSummary.matches?(hd(proven), resource: %{"service.name" => "web"})
    assert TraceSummary.matches?(hd(unproven), resource: %{"service.name" => "web"})
  end

  test "attribute value sets prune only what every row proves" do
    row = fn route, extra ->
      %{
        trace_id: Base.encode16(<<1::128>>, case: :lower),
        service: "kura-eu",
        resource: %{"service.namespace" => "kura"},
        attributes: Map.merge(%{"http.route" => route, "http.response.status_code" => 200}, extra)
      }
    end

    summary = TraceSummary.build([row.("/up", %{}), row.("/metrics", %{"url.path" => String.duplicate("x", 200)})])
    summary = TraceSummary.parse(TraceSummary.to_wire(summary))
    may? = &TraceSummary.matches?(summary, &1)

    assert may?.(attributes_regex: %{"http.route" => "/metrics|/v1/cache.*"})
    refute may?.(attributes_regex: %{"http.route" => "/api/cache.*"})
    refute may?.(attributes: %{"http.route" => "/api/cache"})
    refute may?.(resource: %{"service.namespace" => "tuist"})
    # Every row's keys are known: a key no row holds as a string cannot match.
    refute may?.(attributes_regex: %{"missing" => ".*"})
    # Non-string wanted values and oversized values are never ruled out; a
    # string never equals an integer projection.
    assert may?.(attributes: %{"http.response.status_code" => 200})
    refute may?.(attributes: %{"http.response.status_code" => "200"})
    assert may?.(attributes: %{"url.path" => "anything"})

    # More distinct values than a set keeps leave the key undecided.
    wide = TraceSummary.build(for n <- 1..20, do: row.("/r/#{n}", %{}))
    assert TraceSummary.matches?(wide, attributes: %{"http.route" => "/other"})

    # A page union proves only what every entry proves: an entry without
    # attribute sets (an older writer) keeps the key undecided.
    entry = &%{"t" => TraceSummary.to_wire(&1)}
    legacy = %{TraceSummary.build([row.("/v1/cache/1", %{})]) | attributes: nil}
    page = TraceSummary.page_summary([entry.(summary), entry.(legacy)])
    assert TraceSummary.page_matches?(page, attributes: %{"http.route" => "/v1/cache/1"})
    page = TraceSummary.page_summary([entry.(summary), entry.(TraceSummary.build([row.("/v1/cache/1", %{})]))])
    assert TraceSummary.page_matches?(page, attributes: %{"http.route" => "/v1/cache/1"})
    refute TraceSummary.page_matches?(page, attributes: %{"http.route" => "/api/cache"})
  end

  test "status and event classes prune only proven sources whose rows cannot match" do
    plain = %{
      trace_id: Base.encode16(<<1::128>>, case: :lower),
      service: "api",
      status: %{"code" => 0},
      events: [],
      otlp: %{"events" => []}
    }

    failing = %{plain | status: %{"code" => 2}}
    with_event = %{plain | events: [%{"name" => "exception"}], otlp: %{"events" => [[]]}}

    requires = fn query ->
      {:ok, {:expression, program}} = TempoSearch.parse(query)
      TraceSummary.requirements(program)
    end

    assert requires.(~s[{ status = error }]) == [:error]
    assert requires.(~s[{ event.exception.type != "" } | select(event.exception.type)]) == [:event]
    assert requires.(~s[{ span.a = "x" } >> { status = error && event.exception.type = "E" }]) == [:error, :event]
    assert requires.(~s[{ status = error || span.a = "x" }]) == []
    assert requires.(~s[{ status != error }]) == []

    for {records, error?, event?} <- [
          {[plain], false, false},
          {[plain, failing], true, false},
          {[with_event], false, true}
        ] do
      summary = TraceSummary.build(records, true)
      assert TraceSummary.parse(TraceSummary.to_wire(summary)) == summary
      assert TraceSummary.matches?(summary, trace_requires: [:error]) == error?
      assert TraceSummary.matches?(summary, trace_requires: [:event]) == event?
      page = TraceSummary.page_summary([%{"t" => TraceSummary.to_wire(summary)}])
      assert TraceSummary.page_matches?(page, trace_requires: [:error]) == error?
      # Without the publication proof nothing is pruned.
      assert TraceSummary.matches?(TraceSummary.build(records), trace_requires: [:error, :event])
    end

    # Rows without typed metadata never prove they have no events.
    legacy = TraceSummary.build([%{plain | otlp: nil}], true)
    assert TraceSummary.matches?(legacy, trace_requires: [:event])
  end
end
