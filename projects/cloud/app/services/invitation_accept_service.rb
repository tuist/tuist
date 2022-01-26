# frozen_string_literal: true

class InvitationAcceptService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def message
        "You are not allowed to accept this invitation."
      end
    end
  end

  attr_reader :token, :user

  def initialize(token:, user:)
    super()
    @token = token
    @user = user
  end

  def call
    invitation = InvitationFetchService.call(token: token)
    raise Error::Unauthorized.new unless invitation.invitee_email == user.email
    user.add_role(:user, invitation.organization)
    invitation.organization
  end
end
