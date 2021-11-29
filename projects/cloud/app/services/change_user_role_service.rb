# frozen_string_literal: true

class ChangeUserRoleService < ApplicationService
  attr_reader :user_id, :organization_id, :current_role, :new_role

  def initialize(user_id:, organization_id:, current_role:, new_role:)
    super()
    @user_id = user_id
    @organization_id = organization_id
    @current_role = current_role
    @new_role = new_role
  end

  def call
    return user unless current_role != new_role
    ActiveRecord::Base.transaction do
      organization = Organization.find(organization_id)
      user = User.find(user_id)
      user.remove_role(current_role, organization)
      user.add_role(new_role, organization)
      user
    end
  end
end
