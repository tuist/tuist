# frozen_string_literal: true

CacheHitRateAverage = Struct.new(:date, :cache_hit_rate_average)

class CacheHitRateAverageService < ApplicationService
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
      .where.not(cacheable_targets: "")

    command_events = if start_date > 1.year.ago
      command_events
        .group_by_day(:created_at, range: start_date..Time.now)
    else
      command_events
        .group_by_month(:created_at, range: start_date..Time.now)
    end

    command_events
      .average(
        "(#{query("local_cache_target_hits")} + #{query("remote_cache_target_hits")}) / #{query("cacheable_targets")}",
      )
      .map { |key, value| CacheHitRateAverage.new(date: key, cache_hit_rate_average: value.nil? ? 0 : value) }
  end

  def query(name)
    "LEAST(array_length(string_to_array((#{name} || ';'), ';'), 1) - 1, char_length(#{name}))::double precision"
  end
end
