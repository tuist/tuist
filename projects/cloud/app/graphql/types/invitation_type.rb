# frozen_string_literal: true

module Types
  class InvitationType < Types::BaseObject
    field :invitee_email, ID, null: false
    field :inviter, UserType, null: false
    field :organization, OrganizationType, null: false
    field :token, String, null: false
    field :id, ID, null: false
  end
end
