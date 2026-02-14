defmodule TuistWeb.API.Schemas.Tests.Test do
  @moduledoc """
  The schema for the test response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "RunsTest",
    type: :object,
    description: "Represents a single test run.",
    properties: %{
      type: %Schema{type: :string, enum: ["test"], description: "The type of the run, which is 'test' in this case"},
      id: %Schema{type: :string, description: "The unique identifier of the test run"},
      duration: %Schema{type: :integer, description: "The duration of the test run in milliseconds"},
      project_id: %Schema{type: :integer, description: "The ID of the Tuist project associated with this test run"},
      url: %Schema{type: :string, description: "The URL to access the test run"},
      test_case_runs: %Schema{
        type: :array,
        description: "The test case runs created by this test run, with their identifiers.",
        items: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, description: "The UUID of the test case run."},
            name: %Schema{type: :string, description: "The name of the test case."},
            module_name: %Schema{type: :string, description: "The module name of the test case."},
            suite_name: %Schema{type: :string, description: "The suite name of the test case."}
          },
          required: [:id, :name, :module_name, :suite_name]
        }
      }
    },
    required: [:type, :id, :duration, :project_id, :url]
  })
end
