defmodule TuistWeb.API.Schemas.CargoBuild do
  @moduledoc false

  alias OpenApiSpex.Schema
  alias Tuist.Cargo.CacheMetrics
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.ReportActor

  def list do
    %Schema{
      title: "CargoBuildList",
      type: :object,
      properties: %{builds: %Schema{type: :array, items: build()}, pagination_metadata: PaginationMetadata},
      required: [:builds, :pagination_metadata]
    }
  end

  def detail do
    build = build()

    %{
      build
      | title: "CargoBuildDetail",
        properties: Map.put(build.properties, :cache, cache()),
        required: [:cache | build.required]
    }
  end

  defp build do
    %Schema{
      title: "CargoBuild",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        actor: ReportActor,
        command: nullable_string("The Cargo subcommand, for example build or check."),
        rust_version: nullable_string("The rustc version."),
        status: %Schema{type: :string, enum: ["success", "failure"]},
        duration_ms: %Schema{type: :integer},
        is_ci: %Schema{type: :boolean},
        git_branch: nullable_string(),
        git_commit_sha: nullable_string(),
        git_ref: nullable_string(),
        ci_provider: nullable_string(),
        ci_run_id: nullable_string(),
        ci_project_handle: nullable_string(),
        ci_host: nullable_string(),
        started_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [
        :id,
        :actor,
        :command,
        :rust_version,
        :status,
        :duration_ms,
        :is_ci,
        :git_branch,
        :git_commit_sha,
        :git_ref,
        :ci_provider,
        :ci_run_id,
        :ci_project_handle,
        :ci_host,
        :started_at,
        :inserted_at
      ]
    }
  end

  defp cache do
    counters = Map.new(CacheMetrics.counters(), &{&1, %Schema{type: :integer, minimum: 0}})

    %Schema{
      title: "CargoBuildCache",
      type: :object,
      nullable: true,
      description:
        "Aggregate cache counters reported by the build, or null when it reported none. Estimated avoided compiler time is not wall-clock savings.",
      properties:
        Map.merge(counters, %{
          task_misses: %Schema{
            type: :integer,
            minimum: 0,
            description: "Tasks compiled rather than reused: misses, unconsulted tasks and verifications."
          },
          hit_rate: %Schema{
            type: :number,
            nullable: true,
            description: "Percentage of task decisions that reused a cached result; null without decisions."
          }
        }),
      required: [:task_misses, :hit_rate | CacheMetrics.counters()]
    }
  end

  defp nullable_string(description \\ nil), do: %Schema{type: :string, nullable: true, description: description}
end
