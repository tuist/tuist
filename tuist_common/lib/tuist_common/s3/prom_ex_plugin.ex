defmodule TuistCommon.S3.PromExPlugin do
  @moduledoc """
  Parameterised PromEx plugin for S3 op metrics. Each consuming service
  passes its own `:prefix` (e.g. `:cache`, `:tuist_registry`) so that
  metric names stay namespaced per service.

  Telemetry events expected: `[prefix, :s3, op]` for op in
  `[:head, :upload, :download, :delete]` with `%{duration: microseconds}`
  measurements and `%{result: atom}` metadata.

  ## Opts

    * `:prefix` — atom prefixed to every metric path / event name
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    prefix = Keyword.fetch!(opts, :prefix)

    [
      op_metrics(prefix, :head, [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000]),
      op_metrics(prefix, :upload, [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000]),
      op_metrics(prefix, :download, [
        10,
        50,
        100,
        500,
        1000,
        5000,
        10_000,
        30_000,
        60_000,
        120_000
      ]),
      op_metrics(prefix, :delete, [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000])
    ]
  end

  defp op_metrics(prefix, op, buckets) do
    event = [prefix, :s3, op]
    tag_values = fn metadata -> %{result: to_string(Map.get(metadata, :result, :unknown))} end

    Event.build(:"#{prefix}_s3_#{op}_event_metrics", [
      counter(
        event ++ [:requests, :total],
        event_name: event,
        description: "S3 #{op} request count by result.",
        tags: [:result],
        tag_values: tag_values
      ),
      distribution(
        event ++ [:duration, :milliseconds],
        event_name: event,
        measurement: :duration,
        unit: {:microsecond, :millisecond},
        description: "S3 #{op} request duration.",
        tags: [:result],
        tag_values: tag_values,
        reporter_options: [buckets: buckets]
      )
    ])
  end
end
