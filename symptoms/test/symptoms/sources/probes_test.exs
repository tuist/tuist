Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.ProbesTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.Probes

  @window %{start: 1_763_301_600, seconds: 60}

  defp series(job, location, values),
    do: {%{"job" => job, "probe" => location, "instance" => "https://tuist.dev"}, values}

  defp collect(series, opts \\ []) do
    stub_prometheus(fn promql ->
      assert promql == "probe_success[900s]"
      matrix(series)
    end)

    {:ok, records} = Probes.collect(@window, prom_opts(opts))
    Map.new(records, &{&1.entity.key, &1})
  end

  test "a failure from 2 locations reaches the cap statistic" do
    records =
      collect([
        series("registry-resolve", "Frankfurt", [{60, 1}, {120, 0}]),
        series("registry-resolve", "Virginia", [{60, 1}, {120, 0}]),
        series("signup", "Frankfurt", [{60, 1}, {120, 1}])
      ])

    assert records["registry_resolve"].statistic == Probes.confirmed_statistic()
    assert records["registry_resolve"].examples == ["registry-resolve@Frankfurt", "registry-resolve@Virginia"]
    # A pass lowers evidence only for its own journey.
    assert records["signup"].statistic == 0.0
  end

  test "two consecutive failures at one location confirm" do
    records =
      collect([
        series("api-health", "Frankfurt", [{60, 0}, {120, 0}]),
        series("api-health", "Virginia", [{60, 1}, {120, 1}])
      ])

    assert records["api"].statistic == Probes.confirmed_statistic()
  end

  test "a single failure at one location is the failing share, not confirmed" do
    records =
      collect([
        series("cache-upload", "Frankfurt", [{60, 1}, {120, 0}]),
        series("cache-upload", "Virginia", [{60, 1}, {120, 1}])
      ])

    # "cache-upload" matches the upload pattern, listed before cache. 1 of 2 pairs failing.
    assert records["test_upload"].statistic == 0.5
  end

  test "an expected journey without samples is unknown; an unreachable Mimir is unknown" do
    test = self()
    expected = [%{environment: "production", service: "probes", kind: "journey", key: "signup"}]
    collect([series("api-health", "Frankfurt", [{60, 1}])], entities: expected, unknown: &send(test, {:unknown, &1, &2}))
    assert_received {:unknown, "probe.journey", ^expected}

    stub_prometheus(fn _ -> {:error, 503} end)
    assert {:unknown, ^expected} = Probes.collect(@window, prom_opts(entities: expected))
  end

  test "all non-finite samples are unknown, not a healthy zero-run journey" do
    test = self()
    signup = %{environment: "production", service: "probes", kind: "journey", key: "signup"}

    records =
      collect(
        [
          series("signup", "Frankfurt", [{60, "NaN"}, {120, "+Inf"}]),
          series("signup", "Virginia", []),
          series("api-health", "Frankfurt", [{120, 1}])
        ],
        entities: [signup],
        unknown: &send(test, {:unknown, &1, &2})
      )

    refute Map.has_key?(records, "signup")
    assert records["api"].n == 1
    assert_received {:unknown, "probe.journey", [^signup]}
  end

  test "empty series in a journey do not hide or dilute valid failing runs" do
    records =
      collect([
        series("signup", "Frankfurt", [{60, "NaN"}]),
        series("signup", "Virginia", [{120, 0}])
      ])

    assert records["signup"].n == 1
    assert records["signup"].statistic == 1.0
  end
end
