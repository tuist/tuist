# frozen_string_literal: true

class ProjectPolicy < ApplicationPolicy
  def show?
    AccountPolicy.new(subject, record.account).show?
  end

  def update?
    AccountPolicy.new(subject, record.account).update?
  end
end
