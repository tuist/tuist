# frozen_string_literal: true

class ProjectPolicy < ApplicationPolicy
  def show?
    if record.account.name == "tuist" && record.name == "tuist"
      return true
    end

    AccountPolicy.new(subject, record.account).show?
  end

  def update?
    AccountPolicy.new(subject, record.account).update?
  end
end
