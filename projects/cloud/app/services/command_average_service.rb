# frozen_string_literal: true

class CommandAverage
  attr_reader :date, :duration_average

  def initialize(date:, duration_average:)
    @date = date
    @duration_average = duration_average
  end
end

class CommandAverageService < ApplicationService
  attr_reader :project_id, :command_name, :user

  def initialize(project_id:, command_name:, user:)
    @project_id = project_id
    @command_name = command_name
    @user = user
    super()
  end

  def call
    project = ProjectFetchService.new.fetch_by_id(project_id: project_id, user: user)

    project.command_events
      .where("created_at > ? AND name = ?", 30.days.ago, command_name)
      .group_by_day(:created_at, range: 30.days.ago..Time.now)
      .average(:duration)
      .map { |key, value| CommandAverage.new(date: key, duration_average: value.nil? ? 0 : value) }
  end
end
