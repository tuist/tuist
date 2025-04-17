defmodule TuistWeb.API.Schemas.Error do
  @moduledoc """
  The schema for the error response.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    properties: %{
      message: %Schema{
        type: :string,
        description: "The error message"
      }
    },
    required: [:message]
  })
end
