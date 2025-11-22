defmodule TuistWeb.API.Schemas.CommandEvent do
  @moduledoc """
  The schema for the command event response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CommandEvent",
    description: "A command event.",
    type: :object,
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "The unique identifier of the command event."
      },
      project_id: %Schema{type: :integer, description: "The project identifier"},
      name: %Schema{type: :string, description: "The name of the command"},
      url: %Schema{type: :string, description: "The URL to the command event"},
      test_run_url: %Schema{
        type: :string,
        nullable: true,
        description: "The URL to the test run, if available"
      }
    },
    required: [:id, :project_id, :name, :url],
    example: %{
      "id" => "123e4567-e89b-12d3-a456-426614174000",
      "project_id" => 123,
      "name" => "build",
      "url" => "https://tuist.dev/my-account/my-project/runs/123e4567-e89b-12d3-a456-426614174000",
      "test_run_url" => "https://tuist.dev/my-account/my-project/tests/test-runs/123e4567-e89b-12d3-a456-426614174000"
    }
  })
end
