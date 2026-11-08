defmodule Pulse.Storage.S3.MetricLabelSummaryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.Record.MetricSample
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.MetricLabelSummary

  defp sample(labels, ts \\ 1), do: %MetricSample{timestamp_ns: ts, value: ts / 1, labels: labels}

  test "complete bounded sets include missing labels and omit high-cardinality values independently" do
    records = for i <- 1..100, do: sample(%{"job" => "api", "instance" => "node-#{i}", "__name__" => "up"}, i)
    assert MetricLabelSummary.build(records) == %{"job" => ["api"]}
    assert MetricLabelSummary.build([sample(%{"job" => "api"}), sample(%{})]) == %{"job" => ["", "api"]}
    assert MetricLabelSummary.build([sample(%{}), sample(%{"later" => "x"})]) == %{"later" => ["", "x"]}
    assert MetricLabelSummary.matches?(%{"job" => ["api"]}, [{"instance", :eq, "unknown"}])
    refute MetricLabelSummary.matches?(%{"job" => ["api"]}, [{"job", :eq, "absent"}])
    assert MetricLabelSummary.matches?(%{"job" => ["api"]}, [{"job", :re, "absent"}])
  end

  test "long values, invalid UTF-8, malformed summaries and excessive sets remain unknown" do
    assert MetricLabelSummary.build([sample(%{"job" => <<255>>})]) == nil
    assert MetricLabelSummary.build([sample(%{"job" => "api"}), sample(%{<<255>> => "x", "job" => "api"})]) == nil
    assert MetricLabelSummary.build([sample(%{"job" => String.duplicate("x", 257)})]) == nil

    for wire <- [
          nil,
          %{},
          %{"job" => []},
          %{"job" => "api"},
          %{"job" => [123]},
          %{"job" => [<<255>>]},
          %{"job" => Enum.map(1..33, &"v#{&1}")}
        ] do
      assert MetricLabelSummary.parse(wire) == nil
      assert MetricLabelSummary.matches?(MetricLabelSummary.parse(wire), [{"job", :eq, "api"}])
    end
  end

  test "shared dictionaries survive persistence and malformed references never prune" do
    segment = Segment.build("x", 1, 1, 1) |> Segment.summarize_metrics([sample(%{"job" => "api"})])
    manifest = Manifest.merge(Manifest.new(), [%{segment | key: "x"}, %{segment | key: "y"}])
    encoded = manifest |> Manifest.encode() |> IO.iodata_to_binary()
    wire = JSON.decode!(encoded)
    assert wire["labels"] == [%{"job" => ["api"]}]
    assert Enum.all?(wire["s"], &(&1["li"] == 0))
    assert {:ok, decoded} = Manifest.decode(encoded)
    assert Map.new(decoded.segments, &{&1.key, &1}) == Map.new(manifest.segments, &{&1.key, &1})

    for reference <- [-1, 999, "bad", nil] do
      invalid = %{
        "v" => 1,
        "labels" => [%{"job" => ["api"]}],
        "s" => [%{"k" => "x", "mn" => 1, "mx" => 1, "li" => reference}]
      }

      assert {:ok, decoded} = invalid |> JSON.encode!() |> Manifest.decode()
      assert hd(decoded.segments).metric_labels == nil
      assert Segment.matches_metrics?(hd(decoded.segments), [{"job", :eq, "any"}])
    end
  end

  test "dictionary budget exhaustion loses only pruning, never segment membership" do
    segments =
      for i <- 1..400 do
        labels = Map.new(1..16, &{"key#{&1}", String.duplicate("x", 180) <> "#{i}"})
        Segment.build("x#{i}", i, i, 1) |> Segment.summarize_metrics([sample(labels, i)])
      end

    wire = Manifest.merge(Manifest.new(), segments) |> Manifest.encode() |> IO.iodata_to_binary() |> JSON.decode!()
    assert IO.iodata_length(JSON.encode_to_iodata!(wire["labels"])) <= 65_536
    assert {:ok, decoded} = wire |> JSON.encode!() |> Manifest.decode()
    assert length(decoded.segments) == length(segments)
    assert Enum.any?(decoded.segments, &is_nil(&1.metric_labels))
  end

  test "labels are chosen across mixed records, fewest values first" do
    records = [
      sample(%{"__name__" => "node_cpu", "cpu" => "0"}),
      sample(%{"namespace" => "tuist-canary", "pod" => "kura-1"})
    ]

    summary = MetricLabelSummary.build(records)
    assert summary == %{"cpu" => ["", "0"], "namespace" => ["", "tuist-canary"], "pod" => ["", "kura-1"]}

    records = for i <- 1..40, do: sample(Map.put(Map.new(1..20, &{"a#{&1}", "#{i}"}), "job", "otel"))
    assert MetricLabelSummary.build(records) == %{"job" => ["otel"]}
  end

  # Values and patterns chosen to catch anchoring, quantifier, escaping,
  # empty-value and flag mistakes. Each pattern is anchored as PromQL does.
  @values ["api", "ap", "api-1", "apix", "", "kura-a-1", "kura-", "a.b", "axb", "a|b", "line\nbreak", "ünï", "API"]
  @patterns [
    "api",
    "ap",
    "api|web",
    "(api|ap)",
    "(?:api-1|)",
    "|api",
    "",
    "ap.*",
    "api-.*",
    "kura-(.*)-.*",
    ".*",
    ".+",
    "a.b",
    "a\\.b",
    "a\\|b",
    "api*",
    "api+",
    "api?",
    "ap{2}",
    "ap[i]",
    "[a]pi",
    "(?i)API",
    "\\Qa.b\\E",
    "line.*",
    "ün.*",
    "(api)|(kura-.*)",
    "(ap)i",
    "api-\\d",
    "\\x61pi",
    "ap(i|x)",
    "(a|b)(c|d)",
    "a.*|b",
    "[|]"
  ]

  # Every matcher decodes a segment and matches values on dirty CPU schedulers,
  # which queue behind other tests' native work under CI contention. Keep all
  # comparisons without the ordinary one-minute test budget.
  @tag timeout: 300_000
  test "regex and inequality pruning equals native matching on complete value sets" do
    :rand.seed(:exsss, {42, 7, 2026})

    # Dashboard variable expansions must stay decidable, not merely safe.
    for pattern <- ["tuist-canary", "a|b|c", "(a|b)", "(?:a|b)", ".*", "kura-.*", "process_xcresult|process_build", ""] do
      assert {_, prefixes} =
               MetricLabelSummary.regex_shape(Pulse.QueryRegex.anchor(pattern))
               |> then(&if(&1 == :any, do: {nil, []}, else: &1))

      assert Enum.all?(prefixes, &elem(&1, 1)), pattern
    end

    for _ <- 1..60 do
      records =
        for i <- 1..Enum.random(1..6) do
          labels = %{"__name__" => Enum.random(@values), "job" => Enum.random(@values)}
          labels = if Enum.random(1..4) == 1, do: Map.delete(labels, "job"), else: labels
          labels = if Enum.random(1..4) == 1, do: Map.delete(labels, "__name__"), else: labels
          sample(labels, i)
        end

      segment = Segment.build("x", 1, 10, length(records)) |> Segment.summarize_metrics(records)
      {:ok, payload, _, _} = S3.encode_segment(:metrics, records)

      for name <- ["job", "__name__"],
          op <- [:re, :nre, :eq, :neq],
          value <- if(op in [:re, :nre], do: @patterns, else: @values) do
        pattern = if op in [:re, :nre], do: Pulse.QueryRegex.anchor(value), else: value
        matchers = [{name, op, pattern}]
        {:ok, found} = S3.decode_segment(:metrics, payload, nil, nil, matchers: matchers)
        kept? = Segment.matches_metrics?(segment, matchers)
        assert found == [] or kept?, inspect({records, matchers})

        # With a complete set, a decidable shape keeps exactly the segments
        # holding at least one matching value.
        values = if name == "__name__", do: segment.metric_names, else: segment.metric_labels[name]
        shape = if op in [:re, :nre], do: MetricLabelSummary.regex_shape(pattern), else: :any

        decidable? =
          shape == :any or (shape != :unknown and Enum.all?(elem(shape, 1), &elem(&1, 1)))

        if values != nil and decidable? do
          ideal? = Enum.any?(values, &value_matches?(op, pattern, &1))
          assert kept? == ideal?, inspect({values, matchers})
        end
      end
    end
  end

  defp value_matches?(:eq, expected, value), do: value == expected
  defp value_matches?(:neq, expected, value), do: value != expected
  defp value_matches?(:re, pattern, value), do: NIF.match_metric_regex(pattern, value)
  defp value_matches?(:nre, pattern, value), do: not NIF.match_metric_regex(pattern, value)

  test "randomized exact-label pruning never excludes native matches" do
    :rand.seed(:exsss, {42, 103, 7})

    for _ <- 1..50 do
      records =
        for i <- 1..50 do
          labels = %{"__name__" => "work", "job" => Enum.random(["api", "", "worker"]), "instance" => "node-#{i}"}
          labels = if rem(i, 3) == 0, do: Map.delete(labels, "job"), else: labels
          sample(labels, i)
        end

      summary = MetricLabelSummary.build(records)
      {:ok, payload, _, _} = S3.encode_segment(:metrics, records)

      for name <- ["job", "instance", "missing"], value <- ["api", "worker", "", "absent", "node-17"] do
        matchers = [{name, :eq, value}]
        {:ok, found} = S3.decode_segment(:metrics, payload, nil, nil, matchers: matchers)
        assert found == [] or MetricLabelSummary.matches?(summary, matchers)
      end
    end
  end
end
