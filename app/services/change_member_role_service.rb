# frozen_string_literal: true

class ChangeMemberRoleService < ApplicationService
  attr_reader :username, :organization_name, :role, :role_changer

  module Error
    class MemberNotFound < CloudError
      attr_reader :username

      def initialize(username)
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

  def initialize(username:, organization_name:, role:, role_changer:)
    super()
    @username = username
    @organization_name = organization_name
    @role = role
    @role_changer = role_changer
  end

  def call
    organization = OrganizationFetchService.call(name: organization_name, user: role_changer)
    begin
      user = Account.find_by!(name: username).owner
      raise Error::MemberNotFound.new(username) unless user.is_a?(User)
    rescue ActiveRecord::RecordNotFound
      raise Error::MemberNotFound.new(username)
    end
    ChangeUserRoleService.call(
      user_id: user.id,
      organization_id: organization.id,
      role: role,
      role_changer: role_changer
    )
    OrganizationMember.new(
      id: user.id,
      name: user.name,
      email: user.email,
      role: role
    )
  end
end
