defmodule Cache.Xcode.PromExPlugin do
  @moduledoc """
  Custom Prometheus metrics for Xcode cache operations.

  Emits counters and distributions for downloads (hits, disk hits/misses, errors)
  and uploads (attempts, successes, duplicates, errors) based on Telemetry events
  executed by `CacheWeb.XcodeController`.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_xcode_event_metrics, [
      # Downloads
      counter(
        [
          :tuist_cache,
          :xcode,
          :download,
          :hits,
          :total
        ],
        event_name: [:cache, :xcode, :download, :hit],
        description: "Total Xcode cache download requests received."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :download,
          :disk_hits,
          :total
        ],
        event_name: [:cache, :xcode, :download, :disk_hit],
        description: "Xcode cache downloads served from local disk."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :download,
          :disk_misses,
          :total
        ],
        event_name: [:cache, :xcode, :download, :disk_miss],
        description: "Xcode cache downloads not found on disk (redirected to remote)."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :download,
          :errors,
          :total
        ],
        event_name: [:cache, :xcode, :download, :error],
        description: "Xcode cache download errors (e.g., S3 presign failures)."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :download,
          :s3_hits,
          :total
        ],
        event_name: [:cache, :xcode, :download, :s3_hit],
        description: "Xcode cache downloads pulled from S3 to local disk."
      ),
      sum(
        [
          :tuist_cache,
          :xcode,
          :download,
          :s3_bytes
        ],
        event_name: [:cache, :xcode, :download, :s3_hit],
        measurement: :size,
        description: "Total bytes downloaded from S3 for Xcode cache."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :download,
          :s3_misses,
          :total
        ],
        event_name: [:cache, :xcode, :download, :s3_miss],
        description: "Xcode cache downloads not found in S3 (404)."
      ),
      distribution(
        [
          :tuist_cache,
          :xcode,
          :download,
          :artifact_size,
          :bytes
        ],
        event_name: [:cache, :xcode, :download, :disk_hit],
        measurement: :size,
        unit: :byte,
        description: "Distribution of artifact sizes downloaded from Xcode cache.",
        reporter_options: [buckets: exponential!(1024, 2, 20)]
      ),
      sum(
        [
          :tuist_cache,
          :xcode,
          :download,
          :bytes
        ],
        event_name: [:cache, :xcode, :download, :disk_hit],
        measurement: :size,
        description: "Total bytes downloaded from Xcode cache disk."
      ),

      # Uploads
      counter(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :attempts,
          :total
        ],
        event_name: [:cache, :xcode, :upload, :attempt],
        description: "Total Xcode cache upload attempts received."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :success,
          :total
        ],
        event_name: [:cache, :xcode, :upload, :success],
        description: "Successful Xcode cache uploads."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :exists,
          :total
        ],
        event_name: [:cache, :xcode, :upload, :exists],
        description: "Uploads skipped because artifact already exists."
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :errors,
          :total
        ],
        event_name: [:cache, :xcode, :upload, :error],
        description: "Xcode cache upload errors.",
        tags: [:reason],
        tag_values: fn metadata -> %{reason: to_string(Map.get(metadata, :reason, :unknown))} end
      ),
      counter(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :cancelled,
          :total
        ],
        event_name: [:cache, :xcode, :upload, :cancelled],
        description: "Xcode cache uploads cancelled by client."
      ),
      sum(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :bytes
        ],
        event_name: [:cache, :xcode, :upload, :success],
        measurement: :size,
        description: "Total bytes uploaded to Xcode cache."
      ),
      distribution(
        [
          :tuist_cache,
          :xcode,
          :upload,
          :artifact_size,
          :bytes
        ],
        event_name: [:cache, :xcode, :upload, :success],
        measurement: :size,
        unit: :byte,
        description: "Distribution of artifact sizes uploaded to Xcode cache.",
        reporter_options: [buckets: exponential!(1024, 2, 20)]
      )
    ])
  end
end
