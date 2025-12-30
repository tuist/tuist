defmodule TuistWeb.API.Schemas.ValidationError do
  @moduledoc """
  The schema for validation error responses.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    properties: %{
      message: %Schema{
        type: :string,
        description: "The error message"
      },
      fields: %Schema{
        type: :object,
        description: "Field-specific validation errors",
        additionalProperties: %Schema{
          type: :array,
          items: %Schema{type: :string}
        }
      }
    },
    required: [:message, :fields]
  })
end
