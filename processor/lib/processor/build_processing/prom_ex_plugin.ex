defmodule Processor.BuildProcessing.PromExPlugin do
  @moduledoc false
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
          tags: [:status],
          unit: {:native, :millisecond}
        ),
        counter(
          [:processor, :build, :total],
          event_name: [:processor, :build, :stop],
          description: "Total builds processed.",
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
          [:processor, :build, :parse, :duration, :milliseconds],
          event_name: [:processor, :build, :parse, :stop],
          measurement: :duration,
          description: "Build parse duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]
          ],
          unit: {:native, :millisecond}
        )
      ]
    )
  end
end
