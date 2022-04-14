# frozen_string_literal: true

module Mutations
  class InviteUser < ::Mutations::BaseMutation
    argument :invitee_email, String, required: true
    argument :organization_id, String, required: true

    def resolve(attributes)
      OrganizationInviteService.new.invite(**attributes, inviter: context[:current_user])
    end
  end
end
