defmodule Pulse.Charts.IngestLimitsTest do
  use Pulse.Test.Case, async: true

  @helm System.find_executable("helm")
  @moduletag skip: is_nil(@helm)
  @chart Path.expand("../../../infra/helm/pulse", __DIR__)
  @values Path.expand("../fixtures/helm/synthetic-values.yaml", __DIR__)

  test "trace and OTLP node limits render their runtime environment variables" do
    assert {manifest, 0} = render("max_trace_nodes=123456,ingestLimits.max_otlp_nodes=234567")
    assert manifest =~ ~r/name: PULSE_INGEST_MAX_TRACE_NODES\s+value: "123456"/
    assert manifest =~ ~r/name: PULSE_INGEST_MAX_OTLP_NODES\s+value: "234567"/
    # Unset by default, so the instance derives it from its memory limit.
    refute manifest =~ "PULSE_INGEST_MAX_CONCURRENT_REQUESTS"
    assert {manifest, 0} = render("max_trace_nodes=123456,ingestBatching.maxConcurrentRequests=24")
    assert manifest =~ ~r/name: PULSE_INGEST_MAX_CONCURRENT_REQUESTS\s+value: "24"/
    assert manifest =~ ~r/name: PULSE_INGEST_RESERVED_REQUESTS_PER_SIGNAL\s+value: ""/
    assert manifest =~ ~r/name: PULSE_INGEST_MAX_PENDING_BYTES\s+value: "67108864"/
  end

  test "metric footer pruning is explicitly opt-in" do
    for {settings, expected} <- [{[], "false"}, {["--set", "metricsFooterPruning.enabled=true"], "true"}] do
      assert {manifest, 0} =
               System.cmd(@helm, ["template", "synthetic", @chart, "-f", @values] ++ settings, stderr_to_stdout: true)

      assert manifest =~ "name: PULSE_METRICS_FOOTER_PRUNING_ENABLED\n              value: \"#{expected}\""
    end
  end

  test "public ingress includes OTLP metrics without exposing private self-monitoring" do
    assert {manifest, 0} =
             System.cmd(
               @helm,
               [
                 "template",
                 "synthetic",
                 @chart,
                 "-f",
                 @values,
                 "--set",
                 "ingress.enabled=true,ingress.host=synthetic.invalid,serviceMonitor.enabled=true"
               ],
               stderr_to_stdout: true
             )

    assert manifest =~ ~r/path: \/v1\/metrics\s+pathType: Exact/
    # The ServiceMonitor's own /metrics path is valid; only ingress list items
    # would expose it publicly.
    assert manifest =~ ~r/path: \/metrics\s/
    refute manifest =~ ~r/^\s*- path: \/metrics\s/m
  end

  test "explicit native source bindings render only deployment configuration" do
    assert {manifest, 0} =
             System.cmd(
               @helm,
               [
                 "template",
                 "synthetic",
                 @chart,
                 "-f",
                 @values,
                 "--set-json",
                 ~s(alerting.sourceBindings=[{"tenant":"staging","uid":"original-prom","type":"native_promql"},{"tenant":"staging","uid":"original-logs","type":"native_logql"}])
               ],
               stderr_to_stdout: true
             )

    assert manifest =~ "name: PULSE_ALERTING_SOURCE_BINDINGS_JSON"
    assert manifest =~ "original-prom"
    assert manifest =~ "native_promql"
    assert manifest =~ "original-logs"
    assert manifest =~ "native_logql"
  end

  test "tenant registry, admin digests and usage metering render and validate" do
    digest = "sha256$" <> String.duplicate("a", 64)

    settings =
      "tenantRegistry.enabled=true,tenantRegistry.cacheTtlMs=15000,usage.enabled=true,admin.tokenHashes[0]=#{digest}"

    assert {manifest, 0} =
             System.cmd(@helm, ["template", "synthetic", @chart, "-f", @values, "--set", settings],
               stderr_to_stdout: true
             )

    assert manifest =~ ~r/name: PULSE_TENANT_REGISTRY_ENABLED\s+value: "true"/
    assert manifest =~ ~r/name: PULSE_TENANT_REGISTRY_CACHE_TTL_MS\s+value: "15000"/
    assert manifest =~ ~r/name: PULSE_USAGE_ENABLED\s+value: "true"/
    assert manifest =~ "PULSE_ADMIN_TOKENS: \"#{Base.encode64(~s(["#{digest}"]))}\""

    assert {message, status} =
             System.cmd(@helm, ["template", "synthetic", @chart, "-f", @values, "--set", "admin.tokenHashes[0]=plain"],
               stderr_to_stdout: true
             )

    assert status != 0
    assert message =~ "admin.tokenHashes"
  end

  test "unknown and nonpositive node settings fail chart validation" do
    for key <- ["max_trace_nodes", "max_otlp_nodes"] do
      assert {message, status} = render("#{key}=0")
      assert status != 0
      assert message =~ "ingestLimits.#{key}"
    end

    assert {message, status} = render("max_unknown_nodes=1")
    assert status != 0
    assert message =~ "unknown setting"
  end

  defp render(settings) do
    System.cmd(@helm, ["template", "synthetic", @chart, "-f", @values, "--set", "ingestLimits.#{settings}"],
      stderr_to_stdout: true
    )
  end
end
