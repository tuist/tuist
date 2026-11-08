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

  def failure do
    %Schema{
      type: :object,
      nullable: true,
      description:
        "Why the operation failed: the exception message and its cause chain, without stack traces. The server redacts credentials and local paths and keeps at most 16 KiB per message and 32 messages per build.",
      properties: %{
        message: %Schema{type: :string},
        truncated: %Schema{type: :boolean, description: "Whether the client shortened the message."}
      },
      required: [:message]
    }
  end

  def failures do
    %Schema{
      type: :array,
      description:
        "Failure messages of the build's failed configuration operations and tasks, in start order. Empty when the build succeeded or the reporting plugin predates failure reporting.",
      items: %Schema{
        title: "GradleBuildFailure",
        type: :object,
        properties: %{
          step_id: %Schema{type: :string, description: "The step ID accepted by getGradleBuildStep."},
          kind: %Schema{type: :string, enum: ["task", "configuration"]},
          title: %Schema{type: :string, description: "The task path or configuration phase."},
          project: %Schema{type: :string, description: "The Gradle build path."},
          target: %Schema{type: :string, description: "The task path or configured project path."},
          message: %Schema{type: :string},
          truncated: %Schema{type: :boolean}
        },
        required: [:step_id, :kind, :title, :project, :target, :message, :truncated]
      }
    }
  end

  def failure_message,
    do: %Schema{type: :string, nullable: true, description: "Why the task failed, when the plugin reported it."}

  defp duration, do: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 604_800_000}
end
