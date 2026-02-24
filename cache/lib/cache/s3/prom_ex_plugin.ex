defmodule Cache.S3.PromExPlugin do
  @moduledoc """
  Prometheus metrics for S3 operations.

  Tracks request rate by result and latency distribution for HEAD, upload,
  download, and delete operations to surface S3 timeouts and availability issues.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      head_metrics(),
      upload_metrics(),
      download_metrics(),
      delete_metrics()
    ]
  end

  defp head_metrics do
    Event.build(:cache_s3_head_event_metrics, [
      counter(
        [:cache, :s3, :head, :requests, :total],
        event_name: [:cache, :s3, :head],
        description: "S3 HEAD request count by result.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end
      ),
      distribution(
        [:cache, :s3, :head, :duration, :milliseconds],
        event_name: [:cache, :s3, :head],
        measurement: :duration,
        unit: {:microsecond, :millisecond},
        description: "S3 HEAD request duration.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end,
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000]]
      )
    ])
  end

  defp upload_metrics do
    Event.build(:cache_s3_upload_event_metrics, [
      counter(
        [:cache, :s3, :upload, :requests, :total],
        event_name: [:cache, :s3, :upload],
        description: "S3 upload request count by result.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end
      ),
      distribution(
        [:cache, :s3, :upload, :duration, :milliseconds],
        event_name: [:cache, :s3, :upload],
        measurement: :duration,
        unit: {:microsecond, :millisecond},
        description: "S3 upload request duration.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end,
        reporter_options: [buckets: [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]]
      )
    ])
  end

  defp download_metrics do
    Event.build(:cache_s3_download_event_metrics, [
      counter(
        [:cache, :s3, :download, :requests, :total],
        event_name: [:cache, :s3, :download],
        description: "S3 download request count by result.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end
      ),
      distribution(
        [:cache, :s3, :download, :duration, :milliseconds],
        event_name: [:cache, :s3, :download],
        measurement: :duration,
        unit: {:microsecond, :millisecond},
        description: "S3 download request duration.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end,
        reporter_options: [buckets: [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]]
      )
    ])
  end

  defp delete_metrics do
    Event.build(:cache_s3_delete_event_metrics, [
      counter(
        [:cache, :s3, :delete, :requests, :total],
        event_name: [:cache, :s3, :delete],
        description: "S3 delete request count by result.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end
      ),
      distribution(
        [:cache, :s3, :delete, :duration, :milliseconds],
        event_name: [:cache, :s3, :delete],
        measurement: :duration,
        unit: {:microsecond, :millisecond},
        description: "S3 delete batch duration.",
        tags: [:result],
        tag_values: fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end,
        reporter_options: [buckets: [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000]]
      )
    ])
  end
end
