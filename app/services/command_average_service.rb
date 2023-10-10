# frozen_string_literal: true

class CommandAverage
  attr_reader :date, :duration_average

  def initialize(date:, duration_average:)
    @date = date
    @duration_average = duration_average
  end
end

class CommandAverageService < ApplicationService
  attr_reader :project_id, :command_name, :user, :start_date

  def initialize(project_id:, command_name:, user:, start_date: 30.days.ago)
    @project_id = project_id
    @command_name = command_name
    @user = user
    @start_date = start_date
    super()
  end

  def call
    project = ProjectFetchService.new.fetch_by_id(project_id: project_id, user: user)

    split_command_name = command_name.split(" ")
    name = split_command_name.first
    if split_command_name.length > 1
      subcommand = command_name.split(" ").drop(1)
    end

    command_events = project.command_events
      .where(created_at: start_date..Time.now, name: name, subcommand: subcommand)

    command_events = if start_date > 1.year.ago
      command_events
        .group_by_day(:created_at, range: start_date..Time.now)
    else
      command_events
        .group_by_month(:created_at, range: start_date..Time.now)
    end

    command_events
      .average(:duration)
      .map { |key, value| CommandAverage.new(date: key, duration_average: value.nil? ? 0 : value) }
  end
end
