# frozen_string_literal: true
module Mutations
  class OrganizationCreate < BaseMutation
    description "Create a new organization"

    # Arguments
    argument :name, String, "The name of the organization", required: true

    # Fields
    field :organization, Types::OrganizationType, null: true do
      description "The created organization"
    end
    field :errors, [String], null: false do
      description "A list of errors if the creation of the organization failed"
    end

    def resolve(name:)
      organization = OrganizationCreateService.call(name: name, admin: context[:current_user])
      {
        organization: organization,
        errors: [],
      }
    end
  end
end
