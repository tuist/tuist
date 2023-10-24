# frozen_string_literal: true

class CommandEventPolicy < ApplicationPolicy
  def show?
    ProjectPolicy.new(subject, record.project).show?
  end

  def update?
    ProjectPolicy.new(subject, record.project).update?
  end
end
