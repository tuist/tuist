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
        remote_cache_lookup_outcome: %Schema{type: :string, enum: ["hit", "miss", "error", "not_requested", "unknown"]}
      },
      required: [:build_path, :task_type, :cacheability]
    }
  end
end
