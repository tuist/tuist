# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :me, UserType, null: false,
      description: "Returns the authenticated user"
    def me
      context[:current_user]
    end

    field :projects, [ProjectType], null: false,
      description: "Returns all available projects for the authenticated user"
    def projects
      context[:current_user].projects
    end

    field :organizations, [OrganizationType], null: false,
      description: "Returns all available organizations for the authenticated user"
    def organizations
      context[:current_user].organizations
    end

    field :accounts, [AccountType], null: false,
      description: "Returns all tied accounts for the authenticated user"
    def accounts
      context[:current_user].accounts
    end
  end
end
