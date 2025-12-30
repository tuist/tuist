defmodule TuistWeb.API.Schemas.Runs.Build do
  @moduledoc """
  The schema for the build response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "RunsBuild",
    type: :object,
    description: "Represents a single build run.",
    properties: %{
      type: %Schema{type: :string, enum: ["build"], description: "The type of the run, which is 'build' in this case"},
      id: %Schema{type: :string, description: "The unique identifier of the build run"},
      duration: %Schema{type: :integer, description: "The duration of the build run in milliseconds"},
      project_id: %Schema{type: :integer, description: "The ID of the Tuist project associated with this build run"},
      url: %Schema{type: :string, description: "The URL to access the build run"}
    },
    required: [:type, :id, :duration, :project_id, :url]
  })
end
