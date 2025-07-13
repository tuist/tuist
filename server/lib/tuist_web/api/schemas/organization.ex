defmodule TuistWeb.API.Schemas.Organization do
  @moduledoc """
  A schema for an organization.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Invitation
  alias TuistWeb.API.Schemas.OrganizationMember

  require OpenApiSpex

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
        enum: ["air", "pro", "enterprise", "none"],
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
        enum: ["google", "okta"],
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
