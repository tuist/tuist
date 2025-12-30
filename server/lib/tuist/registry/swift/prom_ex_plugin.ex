defmodule Tuist.Registry.Swift.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Swift Registry events
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :tuist_registry_swift_event_metrics,
      [
        counter(
          [:tuist, :registry, :swift, :source_archive_downloads, :count],
          event_name: [:analytics, :registry, :swift, :source_archive_download],
          description: "The number of source archives downloaded from the Tuist Swift registry."
        )
      ]
    )
  end
end
