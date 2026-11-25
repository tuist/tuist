Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.PulseTracesTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.Pulse
  alias Symptoms.Sources.PulseTraces
  alias Symptoms.Sources.Support

  # 2025-11-16T14:05:00Z, a multiple of 300: the minute ending here closes a 5-minute window.
  @finish 1_763_301_900
  @route %{environment: "production", service: "tuist-server", kind: "span_server", key: "POST /api/runs"}

  defp count_row(version, spans, errors) do
    %{
      "service_name" => "tuist-server",
      "span_kind" => "SPAN_KIND_SERVER",
      "span_name" => "POST /api/runs",
      "service_version" => version,
      "span_count" => spans,
      "error_count" => errors
    }
  end

  defp bucket_row(bucket, count) do
    %{
      "service_name" => "tuist-server",
      "span_kind" => "SPAN_KIND_SERVER",
      "span_name" => "POST /api/runs",
      "service_version" => "1.4.0",
      "latency_bucket" => bucket,
      "span_count" => count
    }
  end

  defp baseline do
    baselines(%{
      {"trace.error_betabinomial", "POST /api/runs"} => %{p: 0.02, rho: 0.001},
      {"trace.latency", "POST /api/runs"} => %{histogram: %{10 => 90, 20 => 8, 30 => 2}}
    })
  end

  test "error residual sums versions and uses the beta-binomial variance" do
    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM" -> latest(@finish + 60)
        sql =~ "symptoms_trace_counts_1m" -> [count_row("1.4.0", 300, 6), count_row("1.5.0", 100, 10)]
      end
    end)

    window = %{start: @finish, seconds: 60}
    assert {:ok, [record]} = PulseTraces.collect(window, pulse_opts(baseline: baseline()))

    # 16 errors of 400; Var = 400 · 0.02 · 0.98 · (1 + 399 · 0.001) = 7.84 · 1.399 = 10.96816.
    assert record.entity == @route
    assert record.source == "trace.error_betabinomial"
    assert record.phenomenon == :request_errors
    assert record.e == 0.0
    assert_in_delta record.statistic, 8 / :math.sqrt(10.96816), 1.0e-9
    assert record.n == 400
    assert record.impact == %{unit: "failed_requests_per_min", rate: 16.0}
  end

  test "latency exceedance against the baseline p95 and median buckets on 5-minute boundaries" do
    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM" -> latest(@finish)
        sql =~ "latency_bucket" -> [bucket_row(10, 50), bucket_row(20, 30), bucket_row(30, 20)]
        sql =~ "symptoms_trace_counts_1m" -> [count_row("1.4.0", 100, 2)]
      end
    end)

    window = %{start: @finish - 60, seconds: 60}
    assert {:ok, records} = PulseTraces.collect(window, pulse_opts(baseline: baseline()))
    by_source = Map.new(records, &{&1.source, &1})

    # Baseline 100 spans: p95 falls in bucket 20 (cumulative 98), 2% above it;
    # the window has 20 of 100 above: (20 - 2) / sqrt(100 · 0.02 · 0.98) = 18 / 1.4.
    p95 = by_source["trace.latency_p95"]
    assert p95.window_seconds == 300
    assert p95.window_start == DateTime.from_unix!(@finish - 300)
    assert_in_delta p95.statistic, 18 / 1.4, 1.0e-9
    assert_in_delta p95.expected, 0.02, 1.0e-12

    # Median bucket 10, 10% above; the window has 50 above: (50 - 10) / sqrt(9) = 40 / 3.
    assert_in_delta by_source["trace.latency_p50"].statistic, 40 / 3, 1.0e-9
    assert by_source["trace.latency_p95"].impact.rate == 4.0
  end

  test "a lagging flow is unknown, never zero" do
    stub_pulse(fn sql -> if sql =~ "AS latest FROM", do: latest(@finish), else: flunk("read #{sql}") end)

    assert {:unknown, [@route]} =
             PulseTraces.collect(%{start: @finish, seconds: 60}, pulse_opts(entities: [@route]))
  end

  test "complete tables still report expected entities missing from counts or latency" do
    missing = %{@route | key: "GET /missing"}
    test = self()

    for {counts, buckets, unknown_stream} <- [
          {[], [bucket_row(10, 100)], "trace.error_betabinomial"},
          {[count_row("1.4.0", 100, 2)], [], "trace.latency_p95"}
        ] do
      stub_pulse(fn sql ->
        cond do
          sql =~ "AS latest FROM" -> latest(@finish)
          sql =~ "latency_bucket" -> buckets
          true -> counts
        end
      end)

      opts = pulse_opts(entities: [@route, missing], baseline: baseline(), unknown: &send(test, {:unknown, &1, &2}))
      assert {:ok, records} = PulseTraces.collect(%{start: @finish - 60, seconds: 60}, opts)
      assert records != []
      assert_received {:unknown, ^unknown_stream, entities}
      assert MapSet.new(entities) == MapSet.new([@route, missing])
      assert_received {:unknown, _, [^missing]}
    end
  end

  test "zero-volume count rows are unknown, while observed entities without baselines are not missing" do
    stub_pulse(fn sql ->
      if sql =~ "AS latest FROM", do: latest(@finish + 60), else: [count_row("1.4.0", 0, 0)]
    end)

    test = self()
    opts = pulse_opts(entities: [@route], baseline: baseline(), unknown: &send(test, {:unknown, &1, &2}))
    assert {:ok, []} = PulseTraces.collect(%{start: @finish, seconds: 60}, opts)
    assert_received {:unknown, "trace.error_betabinomial", [@route]}

    stub_pulse(fn sql ->
      if sql =~ "AS latest FROM", do: latest(@finish + 60), else: [count_row("1.4.0", 10, 0)]
    end)

    assert {:ok, []} = PulseTraces.collect(%{start: @finish, seconds: 60}, Keyword.delete(opts, :baseline))
    refute_received {:unknown, _, _}
  end

  test "an unreachable Pulse is unknown" do
    stub_pulse(fn _sql -> {:error, 503} end)
    assert {:unknown, [@route]} = PulseTraces.collect(%{start: @finish, seconds: 60}, pulse_opts(entities: [@route]))
  end

  test "an entity without a baseline is reported for the catalogue, not scored" do
    stub_pulse(fn sql ->
      if sql =~ "AS latest FROM", do: latest(@finish + 60), else: [count_row("1.4.0", 10, 1)]
    end)

    test = self()
    opts = pulse_opts(discovered: &send(test, {:discovered, &1}))
    assert {:ok, []} = PulseTraces.collect(%{start: @finish, seconds: 60}, opts)
    assert_received {:discovered, [@route]}
  end

  test "queries read-only, against the public database, bounded and with escaped literals" do
    stub_pulse(fn sql -> if sql =~ "AS latest FROM", do: latest(@finish + 60), else: [] end)
    PulseTraces.collect(%{start: @finish, seconds: 60}, pulse_opts())

    assert_received {:sql, _latest, request}
    assert request.headers["x-pulse-db-name"] == ["public"]
    assert request.options.auth == {:basic, "symptoms:read-only"}
    assert_received {:sql, sql, _}

    assert sql =~
             "time_window >= to_timestamp_seconds(#{@finish}) AND time_window < to_timestamp_seconds(#{@finish + 60})"

    assert sql =~ ~r/LIMIT 20001$/
    assert Pulse.literal("it's") == "'it''s'"
  end

  test "more rows than the bound fail instead of truncating" do
    stub_pulse(fn sql ->
      if sql =~ "AS latest FROM", do: latest(@finish + 60), else: [count_row("a", 1, 0), count_row("b", 1, 0)]
    end)

    assert {:unknown, []} =
             PulseTraces.collect(
               %{start: @finish, seconds: 60},
               pulse_opts(pulse: [base_url: "http://p", token: "t", max_rows: 1])
             )
  end

  test "per-version counts for the deploy comparison" do
    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM" -> latest(@finish)
        sql =~ "latency_bucket" -> [bucket_row(12, 7)]
        true -> [count_row("1.4.0", 300, 6), count_row("1.5.0", 100, 10)]
      end
    end)

    assert {:ok, %{@route => versions}} = PulseTraces.version_stats(%{start: @finish - 900, seconds: 900}, pulse_opts())
    assert versions["1.4.0"] == %{spans: 300, errors: 6, histogram: %{12 => 7}}
    assert versions["1.5.0"] == %{spans: 100, errors: 10, histogram: %{}}
  end

  test "a new service version is a deploy change" do
    start = @finish - 60

    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM" ->
          latest(@finish)

        sql =~ "first_seen" ->
          [
            %{
              "service_name" => "tuist-server",
              "service_version" => "1.4.0",
              "first_seen" => start - 7200,
              "last_seen" => start
            },
            %{
              "service_name" => "tuist-server",
              "service_version" => "1.5.0",
              "first_seen" => start,
              "last_seen" => start
            },
            %{"service_name" => "kura", "service_version" => "0.9.1", "first_seen" => start - 600, "last_seen" => start}
          ]

        # Entities per version: POST /api/runs served both, GET /old only the old one.
        sql =~ "SELECT DISTINCT service_name, span_kind, span_name, service_version" ->
          [
            Map.take(count_row("1.4.0", 0, 0), ~w(service_name span_kind span_name service_version)),
            Map.take(count_row("1.5.0", 0, 0), ~w(service_name span_kind span_name service_version)),
            %{
              "service_name" => "tuist-server",
              "span_kind" => "SPAN_KIND_SERVER",
              "span_name" => "GET /old",
              "service_version" => "1.4.0"
            }
          ]
      end
    end)

    assert {:ok, [change]} = PulseTraces.changes(%{start: start, seconds: 60}, pulse_opts())
    assert %{kind: :deploy, ref: "1.5.0", service: "tuist-server", before: "1.4.0", after: "1.5.0", at: ^start} = change
    assert change.touched_entities == [@route]
  end

  test "each window reports per-version counts, with histograms and p95 on 5-minute boundaries" do
    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM" -> latest(@finish)
        sql =~ "latency_bucket" -> [bucket_row(10, 95), bucket_row(20, 5)]
        sql =~ "symptoms_trace_counts_1m" -> [count_row("1.4.0", 100, 2)]
      end
    end)

    test = self()
    opts = pulse_opts(put_version_counts: &send(test, {:counts, &1}))
    PulseTraces.collect(%{start: @finish - 60, seconds: 60}, opts)

    assert_received {:counts, [minute]}
    assert %{version: "1.4.0", window_seconds: 60, errors: 2, total: 100} = minute
    refute Map.has_key?(minute, :histogram)

    assert_received {:counts, [five]}
    assert %{window_seconds: 300, histogram: %{10 => 95, 20 => 5}} = five
    # 95 of 100 reach the p95 in bucket 10, so p95 is the bucket's upper bound 1.1^11 ms.
    assert_in_delta five.p95_ms, :math.pow(1.1, 11), 1.0e-9
  end

  test "baseline fit from sums matches the windowed fit" do
    # Windows {1, 100} and {9, 100}: Σx 10, Σn 200, Σn(n-1) 19800, Σx² 82, Σxn 1000, Σn² 20000.
    fit =
      Support.beta_binomial_from_sums(%{
        "errors" => 10,
        "total" => 200,
        "pairs" => 19_800,
        "errors_sq" => 82,
        "errors_total" => 1000,
        "total_sq" => 20_000
      })

    # Σ (x - np)² = 82 - 2 · 0.05 · 1000 + 0.0025 · 20000 = 32 → rho = (32 / 0.0475 - 200) / 19800.
    assert_in_delta fit.p, 0.05, 1.0e-12
    assert_in_delta fit.rho, (32 / 0.0475 - 200) / 19_800, 1.0e-12
  end
end
