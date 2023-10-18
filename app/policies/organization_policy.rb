# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def show?
    if subject.is_a?(User)
      subject.has_role?(:user, record) || subject.has_role?(:admin, record)
    else
      false
    end
  end

  def update?
    if subject.is_a?(User)
      subject.has_role?(:admin, record)
    else
      false
    end
  end
end
