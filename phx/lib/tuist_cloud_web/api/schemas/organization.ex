defmodule TuistCloudWeb.API.Schemas.Organization do
  @moduledoc """
  A schema for an organization.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.{OrganizationMember, Invitation}

  OpenApiSpex.schema(%{
    type: :object,
    description: "An organization",
    properties: %{
      id: %Schema{
        type: :number,
        description: "The organization's unique identifier"
      },
      name: %Schema{
        type: :string,
        description: "The organization's name"
      },
      plan: %Schema{
        type: :string,
        enum: ["team"],
        description: "The plan associated with the organization"
      },
      members: %Schema{
        type: :array,
        description: "A list of organization members",
        items: OrganizationMember
      },
      invitations: %Schema{
        type: :array,
        description: "A list of organization invitations",
        items: Invitation
      },
      sso_provider: %Schema{
        type: :string,
        enum: ["google"],
        description: "The SSO provider set up for the organization"
      },
      sso_organization_id: %Schema{
        type: :string,
        description: "The organization ID associated with the SSO provider"
      }
    },
    required: [:id, :name, :plan, :members, :invitations]
  })
end
