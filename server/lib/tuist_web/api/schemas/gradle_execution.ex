defmodule TuistWeb.API.Schemas.GradleExecution do
  @moduledoc false
  alias OpenApiSpex.Schema

  def task do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        build_path: %Schema{type: :string, maxLength: 1024},
        task_type: %Schema{type: :string, maxLength: 1024},
        cacheability: %Schema{type: :string, enum: ["cacheable", "disabled", "unknown"]},
        incremental: %Schema{type: :boolean, nullable: true},
        remote_cache_lookup_outcome: %Schema{type: :string, enum: ["hit", "miss", "error", "not_requested", "unknown"]},
        remote_cache_download_duration_ms: duration(),
        remote_cache_upload_duration_ms: duration()
      },
      required: [:build_path, :task_type, :cacheability]
    }
  end

  defp duration, do: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 604_800_000}
end
