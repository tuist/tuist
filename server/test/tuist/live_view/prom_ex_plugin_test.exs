defmodule Tuist.LiveView.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Tuist.LiveView.PromExPlugin
  alias Tuist.Telemetry

  test "labels the histogram with the view module and the outcome" do
    assert PromExPlugin.tag_values(%{view: TuistWeb.ModulesLive, result: :exception}) ==
             %{view: "TuistWeb.ModulesLive", result: "exception"}
  end

  test "exports one duration histogram for the assign_async event" do
    [%{metrics: [metric]}] = PromExPlugin.event_metrics([])

    assert metric.name == [:tuist, :live_view, :assign_async, :duration, :milliseconds]
    assert metric.event_name == Telemetry.event_name_live_view_assign_async()
    assert metric.tags == [:view, :result]
  end
end
