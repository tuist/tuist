defmodule TuistWeb.API.Schemas.Module do
  @moduledoc """
  The schema for a project's module.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    required: [:name, :project_identifier, :hash],
    properties: %{
      name: %Schema{
        type: :string,
        description: "A name of the module"
      },
      project_identifier: %Schema{
        type: :string,
        description: "Project's relative path from the root of the repository"
      },
      hash: %Schema{
        type: :string,
        description: "A hash that represents the module."
      }
    }
  })
end
