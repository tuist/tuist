# frozen_string_literal: true

class CommandCacheHitRateService < ApplicationService
  attr_reader :command_event

  def initialize(command_event:)
    @command_event = command_event
    super()
  end

  def call
    if command_event.cacheable_targets == nil &&
        command_event.local_cache_target_hits == nil &&
        command_event.remote_cache_target_hits == nil
      return
    end
    all_cache_hits =
    command_event.local_cache_target_hits.split(";").length + command_event.remote_cache_target_hits.split(";").length
    (all_cache_hits.to_f / command_event.cacheable_targets.split(";").length.to_f).ceil(2)
  end
end
