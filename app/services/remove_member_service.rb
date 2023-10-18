# frozen_string_literal: true

class RemoveMemberService < ApplicationService
  attr_reader :username, :organization_name, :remover

  module Error
    class MemberNotFound < CloudError
      attr_reader :username

      def initialize(username)
        super
        @username = username
      end

      def message
        "User #{username} was not found"
      end

      def status_code
        :not_found
      end
    end
  end

  def initialize(username:, organization_name:, remover:)
    super()
    @username = username
    @organization_name = organization_name
    @remover = remover
  end

  def call
    organization = OrganizationFetchService.call(name: organization_name, subject: remover)
    begin
      user = Account.find_by!(name: username).owner
      raise Error::MemberNotFound, username unless user.is_a?(User)
    rescue ActiveRecord::RecordNotFound
      raise Error::MemberNotFound, username
    end
    RemoveUserService.call(
      user_id: user.id,
      organization_id: organization.id,
      remover: remover,
    )
  end
end
