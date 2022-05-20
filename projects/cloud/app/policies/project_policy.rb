# frozen_string_literal: true

class ProjectPolicy < ApplicationPolicy
  def show?
    AccountPolicy.new(user, record.account).show?
  end

  def update?
    AccountPolicy.new(user, record.account).update?
  end
end
