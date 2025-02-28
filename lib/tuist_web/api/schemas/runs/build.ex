defmodule TuistWeb.API.Schemas.Runs.Build do
  @moduledoc """
  The schema for the build response.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "RunsBuild",
    type: :object,
    description: "Represents a single build run.",
    properties: %{
      id: %Schema{type: :string},
      duration: %Schema{type: :integer},
      project_id: %Schema{type: :integer}
    },
    required: [:id, :duration, :project_id]
  })
end
