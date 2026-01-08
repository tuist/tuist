defmodule Cache.CAS.PromExPlugin do
  @moduledoc """
  Custom Prometheus metrics for CAS (Content Addressable Storage) operations.

  Emits counters and distributions for downloads (hits, disk hits/misses, errors)
  and uploads (attempts, successes, duplicates, errors) based on Telemetry events
  executed by `CacheWeb.CASController`.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_cas_event_metrics, [
      # Downloads
      counter(
        [
          :tuist_cache,
          :cas,
          :download,
          :hits,
          :total
        ],
        event_name: [:cache, :cas, :download, :hit],
        description: "Total CAS download requests received."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :download,
          :disk_hits,
          :total
        ],
        event_name: [:cache, :cas, :download, :disk_hit],
        description: "CAS downloads served from local disk."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :download,
          :disk_misses,
          :total
        ],
        event_name: [:cache, :cas, :download, :disk_miss],
        description: "CAS downloads not found on disk (redirected to remote)."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :download,
          :errors,
          :total
        ],
        event_name: [:cache, :cas, :download, :error],
        description: "CAS download errors (e.g., S3 presign failures)."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :download,
          :s3_hits,
          :total
        ],
        event_name: [:cache, :cas, :download, :s3_hit],
        description: "CAS downloads pulled from S3 to local disk."
      ),
      sum(
        [
          :tuist_cache,
          :cas,
          :download,
          :s3_bytes
        ],
        event_name: [:cache, :cas, :download, :s3_hit],
        measurement: :size,
        description: "Total bytes downloaded from S3 for CAS."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :download,
          :s3_misses,
          :total
        ],
        event_name: [:cache, :cas, :download, :s3_miss],
        description: "CAS downloads not found in S3 (404)."
      ),
      distribution(
        [
          :tuist_cache,
          :cas,
          :download,
          :artifact_size,
          :bytes
        ],
        event_name: [:cache, :cas, :download, :disk_hit],
        measurement: :size,
        unit: :byte,
        description: "Distribution of artifact sizes downloaded from CAS.",
        reporter_options: [buckets: exponential!(1024, 2, 20)]
      ),
      sum(
        [
          :tuist_cache,
          :cas,
          :download,
          :bytes
        ],
        event_name: [:cache, :cas, :download, :disk_hit],
        measurement: :size,
        description: "Total bytes downloaded from CAS disk."
      ),

      # Uploads
      counter(
        [
          :tuist_cache,
          :cas,
          :upload,
          :attempts,
          :total
        ],
        event_name: [:cache, :cas, :upload, :attempt],
        description: "Total CAS upload attempts received."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :upload,
          :success,
          :total
        ],
        event_name: [:cache, :cas, :upload, :success],
        description: "Successful CAS uploads."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :upload,
          :exists,
          :total
        ],
        event_name: [:cache, :cas, :upload, :exists],
        description: "Uploads skipped because artifact already exists."
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :upload,
          :errors,
          :total
        ],
        event_name: [:cache, :cas, :upload, :error],
        description: "CAS upload errors.",
        tags: [:reason],
        tag_values: fn metadata -> %{reason: to_string(Map.get(metadata, :reason, :unknown))} end
      ),
      counter(
        [
          :tuist_cache,
          :cas,
          :upload,
          :cancelled,
          :total
        ],
        event_name: [:cache, :cas, :upload, :cancelled],
        description: "CAS uploads cancelled by client."
      ),
      sum(
        [
          :tuist_cache,
          :cas,
          :upload,
          :bytes
        ],
        event_name: [:cache, :cas, :upload, :success],
        measurement: :size,
        description: "Total bytes uploaded to CAS."
      ),
      distribution(
        [
          :tuist_cache,
          :cas,
          :upload,
          :artifact_size,
          :bytes
        ],
        event_name: [:cache, :cas, :upload, :success],
        measurement: :size,
        unit: :byte,
        description: "Distribution of artifact sizes uploaded to CAS.",
        reporter_options: [buckets: exponential!(1024, 2, 20)]
      )
    ])
  end
end
