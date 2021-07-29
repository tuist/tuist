# frozen_string_literal: true
module Types
  class QueryType < Types::BaseObject
    # Add `node(id: ID!) and `nodes(ids: [ID!]!)`
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    # Fields
    field :me, UserType, "Returns the authenticated user.", null: false

    # Resolvers
    def me
      context[:current_user]
    end
  end
end
