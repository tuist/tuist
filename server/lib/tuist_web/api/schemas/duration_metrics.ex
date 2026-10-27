defmodule TuistWeb.API.Schemas.DurationMetrics do
  @moduledoc """
  The schema for time-bucketed build or test duration metrics.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  @series %Schema{
    type: :object,
    description: "A duration series. Values are aligned with the `dates` array and expressed in milliseconds.",
    required: [:values, :total],
    properties: %{
      values: %Schema{
        type: :array,
        items: %Schema{type: :number, nullable: true},
        description: "Duration per time bucket, in milliseconds. Buckets with no runs are 0."
      },
      total: %Schema{
        type: :number,
        description: "Duration aggregated across the whole time range, in milliseconds."
      }
    }
  }

  OpenApiSpex.schema(%{
    type: :object,
    description:
      "Time-bucketed duration metrics for build or test runs. The bucket granularity (hour, day, or month) is derived from the requested time range.",
    required: [:dates, :average, :p50, :p90, :p99, :trend],
    properties: %{
      dates: %Schema{
        type: :array,
        items: %Schema{type: :integer, format: :int64},
        description: "Unix timestamps in seconds for the start of each time bucket."
      },
      average: @series,
      p50: @series,
      p90: @series,
      p99: @series,
      trend: %Schema{
        type: :number,
        description:
          "Percentage change in the average duration compared to the immediately preceding period of the same length."
      }
    }
  })
end
