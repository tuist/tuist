# frozen_string_literal: true

class ChangeUserRoleService < ApplicationService
  attr_reader :user_id, :organization_id, :role, :acting_user

  module Error
    Unauthorized = Class.new(StandardError)
  end

  def initialize(user_id:, organization_id:, role:, acting_user:)
    super()
    @user_id = user_id
    @organization_id = organization_id
    @role = role
    @acting_user = acting_user
  end

  def call
    user = User.find(user_id)
    current_role = user.roles.find_by(resource_type: "Organization", resource_id: organization_id)
    return user if current_role == role
    ActiveRecord::Base.transaction do
      organization = Organization.find(organization_id)
      raise Error::Unauthorized unless OrganizationPolicy.new(acting_user, organization).update?
      user.remove_role(current_role.name, organization)
      user.add_role(role, organization)
      user
    end
  end
end
