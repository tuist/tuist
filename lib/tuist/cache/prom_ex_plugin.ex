defmodule Tuist.Cache.PromExPlugin do
  @moduledoc """
  Defines custom Prometheus metrics for the Tuist cache events
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :tuist_cache_event_metrics,
      [
        counter(
          [:tuist, :cache, :uploads, :total],
          event_name: [:analytics, :cache_artifact, :upload],
          description: "The number of uploads to the cache."
        ),
        sum(
          [:tuist, :cache, :uploaded, :bytes],
          event_name: [:analytics, :cache_artifact, :upload],
          description: "The total bytes uploaded to the cache.",
          measurement: :size
        ),
        counter(
          [:tuist, :cache, :downloads, :total],
          event_name: [:analytics, :cache_artifact, :download],
          description: "The number of downloads from the cache."
        ),
        sum(
          [:tuist, :cache, :downloaded, :bytes],
          event_name: [:analytics, :cache_artifact, :download],
          description: "The total bytes downloaded from the cache.",
          measurement: :size
        )
      ]
    )
  end
end
