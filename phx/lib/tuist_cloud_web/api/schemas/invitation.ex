defmodule TuistCloudWeb.API.Schemas.Invitation do
  @moduledoc """
  A schema for an invitation.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.User

  OpenApiSpex.schema(%{
    type: :object,
    properties: %{
      id: %Schema{
        description: "The invitation's unique identifier",
        type: :number
      },
      invitee_email: %Schema{
        description: "The email of the invitee",
        type: :string
      },
      organization_id: %Schema{
        description: "The id of the organization the invitee is invited to",
        type: :number
      },
      token: %Schema{
        description: "The token to accept the invitation",
        type: :string
      },
      inviter: User
    },
    required: [:id, :invitee_email, :organization_id, :inviter, :token]
  })
end
