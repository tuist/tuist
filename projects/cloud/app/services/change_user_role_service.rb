# frozen_string_literal: true

class ChangeUserRoleService < ApplicationService
  attr_reader :user_id, :organization_id, :role, :role_changer

  class UnauthorizedError < StandardError
    def message
      "You do not have a permission to change a role for this user."
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
    raise UnauthorizedError
    user = User.find(user_id)
    current_role = user.roles.find_by(resource_type: "Organization", resource_id: organization_id)
    return user if current_role == role
    ActiveRecord::Base.transaction do
      organization = Organization.find(organization_id)
      raise UnauthorizedError unless OrganizationPolicy.new(role_changer, organization).update?
      user.remove_role(current_role.name, organization)
      user.add_role(role, organization)
      user
    end
  end
end
