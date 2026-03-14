defmodule Processor.BuildProcessing.PromExPlugin do
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :processor_build_processing_event_metrics,
      [
        distribution(
          [:processor, :build, :duration, :milliseconds],
          event_name: [:processor, :build, :stop],
          measurement: :duration,
          description: "Build processing duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000, 300_000, 600_000]
          ],
          tag_values: &extract_status/1,
          tags: [:status],
          unit: {:native, :millisecond}
        ),
        counter(
          [:processor, :build, :total],
          event_name: [:processor, :build, :stop],
          description: "Total builds processed.",
          tag_values: &extract_status/1,
          tags: [:status]
        ),
        distribution(
          [:processor, :s3, :download, :duration, :milliseconds],
          event_name: [:processor, :s3, :download, :stop],
          measurement: :duration,
          description: "S3 download duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000]
          ],
          unit: {:native, :millisecond}
        ),
        distribution(
          [:processor, :s3, :download, :size, :bytes],
          event_name: [:processor, :s3, :download, :stop],
          measurement: :file_size,
          description: "S3 downloaded file size in bytes.",
          reporter_options: [
            buckets: [
              1_000_000,
              10_000_000,
              50_000_000,
              100_000_000,
              500_000_000,
              1_000_000_000
            ]
          ]
        ),
        distribution(
          [:processor, :nif, :parse, :duration, :milliseconds],
          event_name: [:processor, :nif, :parse, :stop],
          measurement: :duration,
          description: "NIF xcactivitylog parse duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]
          ],
          unit: {:native, :millisecond}
        )
      ]
    )
  end

  defp extract_status(%{status: status}), do: %{status: status}
  defp extract_status(_), do: %{status: :unknown}
end
