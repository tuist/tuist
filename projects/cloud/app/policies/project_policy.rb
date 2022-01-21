# frozen_string_literal: true

class ProjectPolicy < ApplicationPolicy
  def show?
    AccountPolicy.new(user, record.account)
  end
end
