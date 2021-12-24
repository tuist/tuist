# frozen_string_literal: true

module Types
  class InvitationType < Types::BaseObject
    field :invitee, ID, null: false
    field :inviter, UserType, null: false
    field :organization, OrganizationType, null: false
  end
end
