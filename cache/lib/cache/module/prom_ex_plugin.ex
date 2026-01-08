defmodule Cache.Module.PromExPlugin do
  @moduledoc """
  Custom Prometheus metrics for Module Cache operations.

  Emits counters and distributions for downloads (hits, disk hits/misses, S3 hits/misses, errors)
  and multipart uploads (starts, parts, completions) based on Telemetry events
  executed by `CacheWeb.ModuleCacheController` and `Cache.S3TransferWorker`.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_module_event_metrics, [
      # Downloads
      counter(
        [:tuist_cache, :module, :download, :hits, :total],
        event_name: [:cache, :module, :download, :hit],
        description: "Total module cache download requests received."
      ),
      counter(
        [:tuist_cache, :module, :download, :disk_hits, :total],
        event_name: [:cache, :module, :download, :disk_hit],
        description: "Module cache downloads served from local disk."
      ),
      sum(
        [:tuist_cache, :module, :download, :disk_bytes],
        event_name: [:cache, :module, :download, :disk_hit],
        measurement: :size,
        description: "Total bytes served from local disk for module cache."
      ),
      distribution(
        [:tuist_cache, :module, :download, :artifact_size, :bytes],
        event_name: [:cache, :module, :download, :disk_hit],
        measurement: :size,
        unit: :byte,
        description: "Distribution of module cache artifact sizes downloaded from disk.",
        reporter_options: [buckets: exponential!(1024, 2, 20)]
      ),
      counter(
        [:tuist_cache, :module, :download, :disk_misses, :total],
        event_name: [:cache, :module, :download, :disk_miss],
        description: "Module cache downloads not found on disk (redirected to S3)."
      ),
      counter(
        [:tuist_cache, :module, :download, :s3_hits, :total],
        event_name: [:cache, :module, :download, :s3_hit],
        description: "Module cache downloads served from S3."
      ),
      sum(
        [:tuist_cache, :module, :download, :s3_bytes],
        event_name: [:cache, :module, :download, :s3_hit],
        measurement: :size,
        description: "Total bytes downloaded from S3 for module cache."
      ),
      counter(
        [:tuist_cache, :module, :download, :s3_misses, :total],
        event_name: [:cache, :module, :download, :s3_miss],
        description: "Module cache downloads not found in S3 (404)."
      ),
      counter(
        [:tuist_cache, :module, :download, :errors, :total],
        event_name: [:cache, :module, :download, :error],
        description: "Module cache download errors.",
        tags: [:reason],
        tag_values: fn metadata -> %{reason: to_string(Map.get(metadata, :reason, :unknown))} end
      ),

      # Multipart uploads
      counter(
        [:tuist_cache, :module, :multipart, :starts, :total],
        event_name: [:cache, :module, :multipart, :start],
        description: "Total multipart module cache uploads started."
      ),
      counter(
        [:tuist_cache, :module, :multipart, :parts, :total],
        event_name: [:cache, :module, :multipart, :part],
        description: "Total multipart upload parts received."
      ),
      sum(
        [:tuist_cache, :module, :multipart, :parts, :bytes],
        event_name: [:cache, :module, :multipart, :part],
        measurement: :size,
        description: "Total bytes received via multipart upload parts."
      ),
      distribution(
        [:tuist_cache, :module, :multipart, :part_size, :bytes],
        event_name: [:cache, :module, :multipart, :part],
        measurement: :size,
        unit: :byte,
        description: "Distribution of multipart upload part sizes.",
        reporter_options: [buckets: exponential!(1024, 2, 14)]
      ),
      counter(
        [:tuist_cache, :module, :multipart, :completions, :total],
        event_name: [:cache, :module, :multipart, :complete],
        description: "Total multipart module cache uploads completed."
      ),
      sum(
        [:tuist_cache, :module, :multipart, :completed, :bytes],
        event_name: [:cache, :module, :multipart, :complete],
        measurement: :size,
        description: "Total bytes uploaded via completed multipart uploads."
      ),
      distribution(
        [:tuist_cache, :module, :multipart, :artifact_size, :bytes],
        event_name: [:cache, :module, :multipart, :complete],
        measurement: :size,
        unit: :byte,
        description: "Distribution of completed multipart upload artifact sizes.",
        reporter_options: [buckets: exponential!(1024, 2, 20)]
      ),
      distribution(
        [:tuist_cache, :module, :multipart, :parts_count, :distribution],
        event_name: [:cache, :module, :multipart, :complete],
        measurement: :parts_count,
        description: "Distribution of parts per completed multipart upload.",
        reporter_options: [buckets: [1, 2, 4, 8, 16, 32, 64, 128]]
      )
    ])
  end
end
