defmodule TuistCloudWeb.API.Schemas.OrganizationMember do
  @moduledoc """
  A schema for an organization member.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    type: :object,
    description: "An organization member",
    properties: %{
      id: %Schema{
        type: :number,
        description: "The organization member's unique identifier"
      },
      email: %Schema{
        type: :string,
        description: "The organization member's email"
      },
      name: %Schema{
        type: :string,
        description: "The organization member's name"
      },
      role: %Schema{
        type: :string,
        enum: ["admin", "user"],
        description: "The organization member's role"
      }
    },
    required: [:id, :email, :name, :role]
  })
end
