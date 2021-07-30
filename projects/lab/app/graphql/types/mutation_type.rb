# frozen_string_literal: true
module Types
  class MutationType < Types::BaseObject
    field :organization_create, mutation: Mutations::OrganizationCreate
  end
end
