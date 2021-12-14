# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def show?
    user.has_role?(:user, record) || user.has_role?(:admin, record)
  end

  def update?
    user.has_role?(:admin, record)
  end
end
