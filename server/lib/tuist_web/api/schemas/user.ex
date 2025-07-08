defmodule TuistWeb.API.Schemas.User do
  @moduledoc """
  A schema for a user.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "A user.",
    properties: %{
      id: %Schema{
        description: "The user's unique identifier",
        type: :number
      },
      email: %Schema{
        description: "The user's email",
        type: :string
      },
      name: %Schema{
        description: "The user's name",
        type: :string
      }
    },
    required: [:id, :email, :name]
  })
end
