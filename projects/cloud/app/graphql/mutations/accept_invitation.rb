# frozen_string_literal: true

module Mutations
  class AcceptInvitation < ::Mutations::BaseMutation
    argument :token, String, required: true

    def resolve(attributes)
      AcceptInvitationService.call(**attributes, user: context[:current_user])
    end
  end
end
