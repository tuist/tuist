defmodule TuistWeb.API.Schemas.GradleExecution do
  @moduledoc false
  alias OpenApiSpex.Schema

  def task do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        build_path: %Schema{type: :string, maxLength: 1024},
        project_path: %Schema{type: :string, maxLength: 1024},
        task_type: %Schema{type: :string, maxLength: 1024},
        cacheability: %Schema{type: :string, enum: ["cacheable", "disabled", "unknown"]},
        caching_disabled_reason: %Schema{type: :string, nullable: true, maxLength: 4096},
        execution_reasons: strings(100),
        incremental: %Schema{type: :boolean, nullable: true},
        remote_cache_lookup_outcome: %Schema{type: :string, enum: ["hit", "miss", "error", "not_requested", "unknown"]},
        remote_cache_lookup_duration_ms: duration(),
        remote_cache_download_duration_ms: duration(),
        remote_cache_upload_duration_ms: duration()
      },
      required: [:build_path, :project_path, :task_type, :cacheability]
    }
  end

  def graph do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        status: %Schema{type: :string, enum: ["complete", "partial", "unavailable"]},
        nodes: %Schema{
          type: :array,
          maxItems: 20_000,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, maxLength: 4096},
              kind: %Schema{type: :string, enum: ["task", "transform"]},
              build_path: %Schema{type: :string, maxLength: 1024},
              project_path: %Schema{type: :string, maxLength: 1024},
              label: %Schema{type: :string, maxLength: 4096},
              dependencies: strings(20_000),
              must_run_after: strings(20_000),
              should_run_after: strings(20_000),
              finalized_by: strings(20_000),
              duration_ms: duration(),
              started_at: %Schema{type: :string, nullable: true, format: :"date-time"}
            },
            required: [:id, :kind, :build_path, :project_path, :label, :dependencies]
          }
        }
      },
      required: [:status, :nodes]
    }
  end

  def options do
    %Schema{type: :object, maxProperties: 20, additionalProperties: %Schema{type: :string, maxLength: 1024}}
  end

  defp strings(limit), do: %Schema{type: :array, maxItems: limit, items: %Schema{type: :string, maxLength: 4096}}
  defp duration, do: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 604_800_000}
end
