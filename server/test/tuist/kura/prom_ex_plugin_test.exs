defmodule Tuist.Kura.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.PromExPlugin
  alias Tuist.Telemetry

  describe "event_metrics/1" do
    test "declares a superseded-deployment counter bound to the superseded telemetry event" do
      [event_group] = PromExPlugin.event_metrics([])

      [counter] = event_group.metrics

      assert counter.name == [:tuist, :kura, :deployments, :superseded, :total]
      assert counter.event_name == Telemetry.event_name_kura_deployment_superseded()
      assert counter.tags == [:region, :provisioner_node_ref, :displacing_image_tag]
    end

    test "derives tag values from the event metadata the context emits" do
      [event_group] = PromExPlugin.event_metrics([])
      [counter] = event_group.metrics

      metadata = %{
        server_id: "server-1",
        region: "eu-central",
        provisioner_node_ref: "kura-tuist-eu-central-1",
        displaced_image_tag: "0.19.0",
        displacing_image_tag: "0.20.0"
      }

      assert counter.tag_values.(metadata) == %{
               region: "eu-central",
               provisioner_node_ref: "kura-tuist-eu-central-1",
               displacing_image_tag: "0.20.0"
             }
    end
  end
end
