# frozen_string_literal: true

module Mutations
  class ResendInvite < ::Mutations::BaseMutation
    argument :invitation_id, String, required: true

    def resolve(attributes)
      OrganizationInviteService.new.resend_invite(**attributes, resender: context[:current_user])
    end
  end
end
