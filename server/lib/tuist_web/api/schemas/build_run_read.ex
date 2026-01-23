defmodule TuistWeb.API.Schemas.BuildRunRead do
  @moduledoc """
  The schema for the build run response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "BuildRunRead",
    type: :object,
    description: "Represents a single build run.",
    required: [:id, :duration, :status, :url, :ran_at],
    properties: %{
      id: %Schema{type: :string, description: "The unique identifier of the build run"},
      duration: %Schema{type: :integer, description: "The duration of the build run in milliseconds"},
      status: %Schema{type: :string, description: "The status of the build run"},
      category: %Schema{type: :string, description: "The category of the build run"},
      scheme: %Schema{type: :string, description: "The scheme that was built"},
      configuration: %Schema{type: :string, description: "The build configuration"},
      git_branch: %Schema{type: :string, description: "The git branch of the build"},
      git_commit_sha: %Schema{type: :string, description: "The git commit SHA of the build"},
      git_ref: %Schema{type: :string, description: "The git ref of the build"},
      is_ci: %Schema{type: :boolean, description: "Whether the build ran in CI"},
      xcode_version: %Schema{type: :string, description: "The Xcode version used"},
      macos_version: %Schema{type: :string, description: "The macOS version used"},
      model_identifier: %Schema{type: :string, description: "The model identifier of the machine"},
      cacheable_tasks_count: %Schema{type: :integer, description: "Number of cacheable tasks"},
      cacheable_task_local_hits_count: %Schema{
        type: :integer,
        description: "Number of local cacheable task hits"
      },
      cacheable_task_remote_hits_count: %Schema{
        type: :integer,
        description: "Number of remote cacheable task hits"
      },
      url: %Schema{type: :string, description: "The URL to access the build run"},
      ran_at: %Schema{
        type: :integer,
        format: :int64,
        description: "Unix timestamp in seconds since epoch (1970-01-01T00:00:00Z)",
        example: 1_715_606_400
      },
      ran_by: %Schema{
        type: :object,
        description: "The account that triggered the run.",
        required: [:handle],
        properties: %{
          handle: %Schema{type: :string, description: "The handle of the account that triggered the run."}
        }
      }
    }
  })
end
