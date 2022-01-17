# frozen_string_literal: true

class InvitationFetchService < ApplicationService
  module Error
    class InvitationNotFound < CloudError
      attr_reader :token

      def initialize(token)
        @token = token
      end

      def message
        "Invitation with the token #{token} could not be found."
      end
    end
  end

  attr_reader :token

  def initialize(token:)
    super()
    @token = token
  end

  def call
    begin
      invitation = Invitation.find_by!(token: token)
    rescue ActiveRecord::RecordNotFound
      raise Error::InvitationNotFound.new(token)
    end
    invitation
  end
end
