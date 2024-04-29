defmodule TuistCloudWeb.API.Schemas.CommandEvent do
  @moduledoc """
  The schema for the command event response.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    type: :object,
    description: "The schema for the command analytics event.",
    required: [:id, :name],
    properties: %{
      id: %Schema{
        type: :number
      },
      name: %Schema{
        type: :string
      }
    }
  })
end
