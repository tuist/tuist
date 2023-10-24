# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def show?
    if subject.is_a?(User)
      subject.has_role?(:user, record) || subject.has_role?(:admin, record)
    elsif subject.is_a?(Project)
      subject.account == record.owner
    else
      false
    end
  end

  def update?
    if subject.is_a?(User)
      subject.has_role?(:admin, record)
    elsif subject.is_a?(Project)
      false
    else
      false
    end
  end
end
