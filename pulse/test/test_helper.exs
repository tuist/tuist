integration_enabled? =
  case System.get_env("PULSE_INTEGRATION") do
    nil -> false
    "" -> false
    "0" -> false
    "false" -> false
    _ -> true
  end

# Optional real SDK/Collector harnesses are never part of the S3 integration job.
# Opt in explicitly with --include collector_bridge, elixir_sdk, or rust_sdk.
# The ingest load test (test/pulse_web/ingest_load_test.exs) runs with --include ingest_load,
# the PromQL scale benchmark (test/pulse/promql/query_scale_bench_test.exs) with --include query_bench.
external = [:collector_bridge, :elixir_sdk, :rust_sdk, :ingest_load, :query_bench]
exclude = if integration_enabled?, do: external, else: [:integration | external]

ExUnit.start(exclude: exclude)
