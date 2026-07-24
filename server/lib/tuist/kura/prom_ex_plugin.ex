defmodule Tuist.Kura.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for Kura control-plane events.
  """
  use PromEx.Plugin

  alias Tuist.Telemetry

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_kura_deployment_event_metrics,
        [
          counter(
            [:tuist, :kura, :deployments, :superseded, :total],
            event_name: Telemetry.event_name_kura_deployment_superseded(),
            measurement: :count,
            description: "A Kura deployment closed as superseded by a newer released image tag.",
            tags: [:region, :provisioner_node_ref, :displacing_image_tag],
            tag_values: &superseded_tag_values/1
          )
        ]
      )
    ]
  end

  defp superseded_tag_values(%{
         region: region,
         provisioner_node_ref: provisioner_node_ref,
         displacing_image_tag: displacing_image_tag
       }) do
    %{region: region, provisioner_node_ref: provisioner_node_ref, displacing_image_tag: displacing_image_tag}
  end
end
