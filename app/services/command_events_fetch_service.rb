# frozen_string_literal: true

class CommandEventsFetchService < ApplicationService
  attr_reader :project_id, :user

  def initialize(project_id:, user:)
    super()
    @project_id = project_id
    @user = user
  end

  def call
    project = ProjectFetchService.new.fetch_by_id(project_id: project_id, subject: user)

    project.command_events.order("created_at DESC")
  end
end
