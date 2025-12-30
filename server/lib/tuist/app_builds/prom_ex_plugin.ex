defmodule Tuist.AppBuilds.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist preview events
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :tuist_preview_event_metrics,
      [
        counter(
          [:tuist, :previews, :uploads, :total],
          event_name: [:analytics, :preview, :upload],
          description: "The number of previews uploaded."
        ),
        counter(
          [:tuist, :previews, :downloads, :total],
          event_name: [:analytics, :preview, :download],
          description: "The number of previews downloaded."
        )
      ]
    )
  end
end
