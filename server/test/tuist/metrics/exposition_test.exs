defmodule Tuist.Metrics.ExpositionTest do
  use ExUnit.Case, async: true

  alias Tuist.Metrics.Exposition

  describe "negotiate/1" do
    test "selects openmetrics when requested" do
      assert Exposition.negotiate("application/openmetrics-text; version=1.0.0,text/plain;q=0.5") == :openmetrics
    end

    test "falls back to prometheus when header is missing" do
      assert Exposition.negotiate(nil) == :prometheus
    end

    test "falls back to prometheus when openmetrics is not present" do
      assert Exposition.negotiate("text/plain; version=0.0.4") == :prometheus
    end
  end

  describe "render/2" do
    test "emits HELP, TYPE and labelled counter samples in prometheus format" do
      snapshot = [
        %{
          metric: "tuist_xcode_cache_events_total",
          type: :counter,
          labels: {"acme/app", "local_hit"},
          value: 4
        }
      ]

      output = snapshot |> Exposition.render(:prometheus) |> IO.iodata_to_binary()

      assert output =~ "# HELP tuist_xcode_cache_events_total"
      assert output =~ "# TYPE tuist_xcode_cache_events_total counter"

      assert output =~
               ~s(tuist_xcode_cache_events_total{project="acme/app",event_type="local_hit"} 4)
    end

    test "emits canonical family name in openmetrics HELP/TYPE and single-_total sample line" do
      snapshot = [
        %{
          metric: "tuist_xcode_cache_events_total",
          type: :counter,
          labels: {"acme/app", "miss"},
          value: 1
        }
      ]

      output = snapshot |> Exposition.render(:openmetrics) |> IO.iodata_to_binary()

      # HELP/TYPE strip the `_total` suffix per the OpenMetrics spec — it's
      # added back on the sample line by convention.
      assert output =~ "# HELP tuist_xcode_cache_events "
      assert output =~ "# TYPE tuist_xcode_cache_events counter"
      assert output =~ ~s(tuist_xcode_cache_events_total{project="acme/app",event_type="miss"} 1)
      # And crucially NOT `tuist_xcode_cache_events_total_total{...}`.
      refute output =~ "tuist_xcode_cache_events_total_total"
      assert String.ends_with?(output, "# EOF\n")
    end

    test "emits histogram bucket series in ascending order with +Inf" do
      snapshot = [
        %{
          metric: "tuist_xcode_build_run_duration_seconds",
          type: :histogram,
          labels: {"acme/app", "App", "false", "success"},
          count: 3,
          sum: 4.5,
          buckets: [
            {0.5, 1},
            {1, 1},
            {2, 3},
            {5, 3},
            {10, 3},
            {30, 3},
            {60, 3},
            {120, 3},
            {300, 3},
            {600, 3},
            {1200, 3}
          ]
        }
      ]

      output = snapshot |> Exposition.render(:prometheus) |> IO.iodata_to_binary()

      assert output =~ ~s(tuist_xcode_build_run_duration_seconds_bucket{)
      assert output =~ ~s(le="0.5")
      assert output =~ ~s(le="+Inf"} 3)
      assert output =~ ~s(tuist_xcode_build_run_duration_seconds_count{)
      assert output =~ ~s(tuist_xcode_build_run_duration_seconds_sum{)
    end

    test "escapes quotes and newlines in label values" do
      snapshot = [
        %{
          metric: "tuist_cli_invocations_total",
          type: :counter,
          labels: {"acme/app", ~s("weird"), "false", "success"},
          value: 1
        }
      ]

      output = snapshot |> Exposition.render(:prometheus) |> IO.iodata_to_binary()

      assert output =~ ~s(command="\\"weird\\"")
    end
  end
end
