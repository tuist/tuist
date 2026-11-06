defmodule TuistWeb.API.Schemas.BuildMetrics do
  @moduledoc "Build health metric responses for Grafana."
  alias OpenApiSpex.Schema

  require OpenApiSpex

  @number %Schema{type: :number, nullable: true}
  @metrics ~w(builds successful_builds failed_builds cancelled_builds success_rate average p50 p90 p99 slow_build_threshold builds_needing_attention cache_time_saved cache_time_saved_samples cache_work_avoided cache_work_avoided_samples)a
  @totals %Schema{type: :object, properties: Map.new(@metrics, &{&1, @number})}
  @series %Schema{type: :object, properties: Map.new(@metrics, &{&1, %Schema{type: :array, items: @number}})}

  OpenApiSpex.schema(%{
    type: :object,
    description:
      "Counts, percentages and durations in milliseconds. Missing rates, durations and unreported cache savings are null. Success rate excludes cancelled builds. Rows are bounded to 100 recent failures or 1000 workloads.",
    properties: %{
      dates: %Schema{type: :array, items: %Schema{type: :integer, format: :int64}},
      series: @series,
      totals: @totals,
      rows: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties:
            Map.merge(@totals.properties, %{
              workload: %Schema{type: :string},
              category: %Schema{type: :string},
              id: %Schema{type: :string},
              build_system: %Schema{type: :string},
              started_at: %Schema{type: :integer, format: :int64},
              duration_ms: @number,
              user: %Schema{type: :string},
              requested_tasks: %Schema{type: :array, items: %Schema{type: :string}},
              failure_category: %Schema{type: :string},
              git_branch: %Schema{type: :string}
            })
        }
      }
    }
  })
end
