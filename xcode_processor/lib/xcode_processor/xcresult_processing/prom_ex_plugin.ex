defmodule XcodeProcessor.XCResultProcessing.PromExPlugin do
  @moduledoc false
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :xcode_processor_xcresult_processing_event_metrics,
      [
        distribution(
          [:xcode_processor, :xcresult, :duration, :milliseconds],
          event_name: [:xcode_processor, :xcresult, :stop],
          measurement: :duration,
          description: "XCResult processing duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000, 300_000, 600_000]
          ],
          tags: [:status],
          unit: {:native, :millisecond}
        ),
        counter(
          [:xcode_processor, :xcresult, :total],
          event_name: [:xcode_processor, :xcresult, :stop],
          description: "Total xcresults processed.",
          tags: [:status]
        ),
        distribution(
          [:xcode_processor, :s3, :download, :duration, :milliseconds],
          event_name: [:xcode_processor, :s3, :download, :stop],
          measurement: :duration,
          description: "S3 download duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000]
          ],
          unit: {:native, :millisecond}
        ),
        distribution(
          [:xcode_processor, :xcresult, :parse, :duration, :milliseconds],
          event_name: [:xcode_processor, :xcresult, :parse, :stop],
          measurement: :duration,
          description: "XCResult parse duration in milliseconds.",
          reporter_options: [
            buckets: [100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]
          ],
          unit: {:native, :millisecond}
        )
      ]
    )
  end
end
