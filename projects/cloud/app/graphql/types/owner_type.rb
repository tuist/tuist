# frozen_string_literal: true

module Types
  class OwnerType < Types::BaseUnion
    possible_types UserType, OrganizationType

    def self.resolve_type(object, context)
      if object.is_a?(User)
        Types::UserType
      elsif object.is_a?(Organization)
        Types::OrganizationType
      end
    end
  end
end
