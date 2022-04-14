# frozen_string_literal: true

module Mutations
  class CancelInvite < ::Mutations::BaseMutation
    argument :invitation_id, String, required: true

    def resolve(attributes)
      OrganizationInviteService.new.cancel_invite(**attributes, remover: context[:current_user])
    end
  end
end
