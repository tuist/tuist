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
        distribution(
          [:tuist, :cache, :upload, :artifact_size, :distribution],
          event_name: [:analytics, :cache_artifact, :upload],
          measurement: :size,
          unit: :byte,
          description: "The distribution of uploaded artifact sizes in bytes.",
          reporter_options: [
            buckets: exponential!(100, 2, 15)
          ]
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
        ),
        distribution(
          [:tuist, :cache, :download, :artifact_size, :distribution],
          event_name: [:analytics, :cache_artifact, :download],
          measurement: :size,
          unit: :byte,
          description: "The distribution of downloaded artifact sizes in bytes.",
          reporter_options: [
            buckets: exponential!(100, 2, 15)
          ]
        )
      ]
    )
  end
end
