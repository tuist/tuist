defmodule TuistWeb.API.Schemas.Runs.Test do
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
      url: %Schema{type: :string, description: "The URL to access the test run"}
    },
    required: [:type, :id, :duration, :project_id, :url]
  })
end
