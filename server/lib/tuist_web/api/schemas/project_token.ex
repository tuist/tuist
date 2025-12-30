defmodule TuistWeb.API.Schemas.ProjectToken do
  @moduledoc """
  The schema for the project token.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "A token to authenticate API requests as a project.",
    properties: %{
      id: %Schema{
        type: :string,
        description: "The token unique identifier."
      },
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "The timestamp of when the token was created."
      }
    },
    required: [:id, :inserted_at]
  })
end
