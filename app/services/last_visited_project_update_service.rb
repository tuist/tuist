# frozen_string_literal: true

class LastVisitedProjectUpdateService < ApplicationService
  attr_reader :id, :user

  def initialize(id:, user:)
    super()
    @id = id
    @user = user
  end

  def call
    user.update(last_visited_project_id: id)
    user
  end
end
