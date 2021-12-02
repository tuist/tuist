# frozen_string_literal: true

class ChangeUserRoleService < ApplicationService
  attr_reader :user_id, :organization_id, :current_role, :new_role, :current_user

  module Error
    Unauthorized = Class.new(StandardError)
  end

  def initialize(user_id:, organization_id:, current_role:, new_role:, current_user:)
    super()
    @user_id = user_id
    @organization_id = organization_id
    @current_role = current_role
    @new_role = new_role
    @current_user = current_user
  end

  def call
    return user if current_role == new_role
    ActiveRecord::Base.transaction do
      organization = Organization.find(organization_id)
      raise Error::Unauthorized unless OrganizationPolicy.new(current_user, organization).update?
      user = User.find(user_id)
      user.remove_role(current_role, organization)
      user.add_role(new_role, organization)
      user
    end
  end
end
