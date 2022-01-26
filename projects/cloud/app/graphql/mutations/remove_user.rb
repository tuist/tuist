# frozen_string_literal: true

module Mutations
  class RemoveUser < ::Mutations::BaseMutation
    argument :user_id, ID, required: true
    argument :organization_id, String, required: true

    type Types::UserType

    def resolve(attributes)
      RemoveUserService.call(**attributes, remover: context[:current_user])
    end
  end
end
