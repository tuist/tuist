# frozen_string_literal: true

class ChangeUserRoleService < ApplicationService
  attr_reader :user_id, :organization_id, :role, :role_changer

  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to change a role for this user."
      end
    end

    class UserNotFound < CloudError
      attr_reader :user_id

      def initialize(user_id)
        @user_id = user_id
      end

      def message
        "User with id #{user_id} was not found"
      end
    end
  end

  def initialize(user_id:, organization_id:, role:, role_changer:)
    super()
    @user_id = user_id
    @organization_id = organization_id
    @role = role
    @role_changer = role_changer
  end

  def call
    begin
      user = User.find(user_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::UserNotFound.new(user_id)
    end
    current_role = user.roles.find_by(resource_type: "Organization", resource_id: organization_id)
    return user if current_role == role

    ActiveRecord::Base.transaction do
      organization = Organization.find(organization_id)
      raise Error::Unauthorized unless OrganizationPolicy.new(role_changer, organization).update?

      user.remove_role(current_role.name, organization)
      user.add_role(role, organization)
      user
    end
  end
end
