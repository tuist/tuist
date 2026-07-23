defmodule Tuist.Kura.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.PromExPlugin
  alias Tuist.Kura.Telemetry

  test "exports the runner-cache reconciliation pause state" do
    [group] = PromExPlugin.event_metrics([])
    [metric] = group.metrics

    assert group.group_name == :tuist_kura_runner_cache_reconciliation_event_metrics
    assert metric.name == [:tuist, :kura, :runner_cache, :reconciliation, :paused]
    assert metric.event_name == Telemetry.event_name_runner_cache_reconciliation()
    assert metric.measurement == :paused
  end

  test "is registered with the application metrics" do
    assert PromExPlugin in Tuist.PromEx.plugins()
  end
end
