defmodule TuistWeb.API.Schemas.Project do
  @moduledoc """
  The schema for the project response.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    type: :object,
    required: [:id, :full_name, :token, :default_branch],
    properties: %{
      id: %Schema{
        type: :number,
        description: "ID of the project"
      },
      full_name: %Schema{
        type: :string,
        description: "The full name of the project (e.g. tuist/tuist)"
      },
      token: %Schema{
        type: :string,
        description: "The token that should be used to authenticate the project. For CI only.",
        deprecated: true
      },
      default_branch: %Schema{
        type: :string,
        description: "The default branch of the project.",
        example: "main"
      }
    }
  })
end
