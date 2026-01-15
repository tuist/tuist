defmodule TuistWeb.API.Schemas.TestRunRead do
  @moduledoc """
  The schema for the test run response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestRunRead",
    type: :object,
    description: "Represents a single test run.",
    required: [:id, :duration, :status, :url, :ran_at],
    properties: %{
      id: %Schema{type: :string, description: "The unique identifier of the test run"},
      duration: %Schema{type: :integer, description: "The duration of the test run in milliseconds"},
      status: %Schema{type: :string, description: "The status of the test run"},
      scheme: %Schema{type: :string, description: "The scheme that was tested"},
      git_branch: %Schema{type: :string, description: "The git branch of the test run"},
      git_commit_sha: %Schema{type: :string, description: "The git commit SHA of the test run"},
      git_ref: %Schema{type: :string, description: "The git ref of the test run"},
      is_ci: %Schema{type: :boolean, description: "Whether the test run ran in CI"},
      xcode_version: %Schema{type: :string, description: "The Xcode version used"},
      macos_version: %Schema{type: :string, description: "The macOS version used"},
      model_identifier: %Schema{type: :string, description: "The model identifier of the machine"},
      build_run_id: %Schema{type: :string, description: "The ID of the associated build run"},
      url: %Schema{type: :string, description: "The URL to access the test run"},
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
