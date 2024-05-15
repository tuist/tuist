defmodule TuistCloudWeb.API.Schemas.Error do
  @moduledoc """
  The schema for the error response.
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

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
