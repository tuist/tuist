defmodule TuistWeb.API.Schemas.MixBuild do
  @moduledoc false

  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.ReportActor

  def list do
    %Schema{
      title: "MixBuildList",
      type: :object,
      properties: %{builds: %Schema{type: :array, items: build()}, pagination_metadata: PaginationMetadata},
      required: [:builds, :pagination_metadata]
    }
  end

  def detail do
    build = build()

    %{
      build
      | title: "MixBuildDetail",
        properties: Map.put(build.properties, :cache, cache()),
        required: [:cache | build.required]
    }
  end

  defp build do
    %Schema{
      title: "MixBuild",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        actor: ReportActor,
        status: %Schema{type: :string, enum: ["success", "failure"]},
        duration_ms: %Schema{type: :integer},
        is_ci: %Schema{type: :boolean},
        elixir_version: nullable_string(),
        otp_version: nullable_string(),
        mix_env: nullable_string(),
        git_branch: nullable_string(),
        git_commit_sha: nullable_string(),
        git_ref: nullable_string(),
        ci_provider: nullable_string(),
        ci_run_id: nullable_string(),
        ci_project_handle: nullable_string(),
        ci_host: nullable_string(),
        custom_metadata: %Schema{
          type: :object,
          properties: %{
            tags: %Schema{type: :array, items: %Schema{type: :string}},
            values: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
          },
          required: [:tags, :values]
        },
        diagnostics_error_count: %Schema{type: :integer},
        diagnostics_warning_count: %Schema{type: :integer},
        started_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [
        :id,
        :actor,
        :status,
        :duration_ms,
        :is_ci,
        :elixir_version,
        :otp_version,
        :mix_env,
        :git_branch,
        :git_commit_sha,
        :git_ref,
        :ci_provider,
        :ci_run_id,
        :ci_project_handle,
        :ci_host,
        :custom_metadata,
        :diagnostics_error_count,
        :diagnostics_warning_count,
        :started_at,
        :inserted_at
      ]
    }
  end

  defp cache do
    durations =
      Map.new(
        ~w(avg_read_duration_us p50_read_duration_us p90_read_duration_us p99_read_duration_us avg_write_duration_us p50_write_duration_us p90_write_duration_us p99_write_duration_us)a,
        &{&1, %Schema{type: :number, nullable: true, description: "Cache operation duration in microseconds."}}
      )

    %Schema{
      title: "MixBuildCache",
      type: :object,
      description: "Dependency cache observations recorded by the build.",
      properties:
        Map.merge(durations, %{
          hits: %Schema{type: :integer, description: "Local and remote hits."},
          local_hits: %Schema{type: :integer},
          remote_hits: %Schema{type: :integer},
          misses: %Schema{type: :integer},
          bypasses: %Schema{type: :integer, description: "Dependencies that skipped the cache."},
          hit_rate: %Schema{
            type: :number,
            nullable: true,
            description: "Hits divided by hits plus misses, as a percentage; null without lookups."
          },
          saved_duration_ms: %Schema{
            type: :integer,
            nullable: true,
            description: "Estimated compilation avoided by hits, not elapsed build savings."
          },
          read_bytes: %Schema{type: :integer, nullable: true},
          write_bytes: %Schema{type: :integer, nullable: true}
        }),
      required:
        Enum.sort([
          :hits,
          :local_hits,
          :remote_hits,
          :misses,
          :bypasses,
          :hit_rate,
          :saved_duration_ms,
          :read_bytes,
          :write_bytes | Map.keys(durations)
        ])
    }
  end

  defp nullable_string, do: %Schema{type: :string, nullable: true}
end
