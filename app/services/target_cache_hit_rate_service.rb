# frozen_string_literal: true

TargetCacheHitRate = Struct.new(:target, :cache_hit_rate, :hits, :misses, :total_count)

class TargetCacheHitRateService < ApplicationService
  attr_reader :project_id, :user, :start_date

  def initialize(project_id:, user:, start_date: 30.days.ago)
    @project_id = project_id
    @user = user
    @start_date = start_date
    super()
  end

  def call
    project = ProjectFetchService.new.fetch_by_id(project_id: project_id, user: user)

    command_events = project.command_events
      .where(created_at: start_date..Time.now)
      .where.not(cacheable_targets: nil)
    targets = command_events
      .pluck(query("cacheable_targets"))
      .flatten
      .uniq
      .reject(&:empty?)

    targets.map { |target_name| target_cache_hit_rate(target_name, command_events) }
  end

  def target_cache_hit_rate(target, command_events)
    hits = 0
    misses = 0

    command_events
      .pluck(query("cacheable_targets"), query("local_cache_target_hits"), query("remote_cache_target_hits"))
      .each do |command_event|
        cacheable_targets = command_event[0]
          .reject(&:empty?)
        local_cache_target_hits = command_event[1]
          .reject(&:empty?)
        remote_cache_target_hits = command_event[2]
          .reject(&:empty?)

        unless cacheable_targets.include?(target)
          next
        end

        if local_cache_target_hits.include?(target) || remote_cache_target_hits.include?(target)
          hits += 1
        else
          misses += 1
        end
      end

    TargetCacheHitRate.new(
      target: target,
      cache_hit_rate: (hits.to_f / (hits + misses)).round(3),
      hits: hits,
      misses: misses,
      total_count: hits + misses,
    )
  end

  def query(name)
    Arel.sql("string_to_array((#{name} || ';'), ';')")
  end
end
