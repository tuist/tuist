# frozen_string_literal: true

class CacheHitRateAverage
  attr_reader :date, :cache_hit_rate_average

  def initialize(date:, cache_hit_rate_average:)
    @date = date
    @cache_hit_rate_average = cache_hit_rate_average
  end
end

class CacheHitRateAverageService < ApplicationService
  attr_reader :project_id, :command_name, :user

  def initialize(project_id:, command_name:, user:)
    @project_id = project_id
    @command_name = command_name
    @user = user
    super()
  end

  def call
    project = ProjectFetchService.new.fetch_by_id(project_id: project_id, user: user)

    split_command_name = command_name.split(" ")
    name = split_command_name.first
    if split_command_name.length > 1
      subcommand = command_name.split(" ").drop(1)
    end

    def query(name)
      "LEAST(array_length(string_to_array((#{name} || ';'), ';'), 1) - 1, char_length(#{name}))::double precision"
    end

    project.command_events
      .where(created_at: 30.days.ago..Time.now, name: name, subcommand: subcommand)
      .where.not(cacheable_targets: "")
      .group_by_day(:created_at, range: 30.days.ago..Time.now)
      .average(
        "(#{query("local_cache_target_hits")} + #{query("remote_cache_target_hits")}) / #{query("cacheable_targets")}",
      )
      .map { |key, value| CacheHitRateAverage.new(date: key, cache_hit_rate_average: value.nil? ? 0 : value) }
  end
end
