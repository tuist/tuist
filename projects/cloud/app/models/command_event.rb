# frozen_string_literal: true

class CommandEvent < ApplicationRecord
  validates :name,
    :duration,
    :client_id,
    :tuist_version,
    :swift_version,
    :macos_version,
    :command_arguments,
    presence: true

  belongs_to :project, optional: false

  def cache_hit_rate
    CommandCacheHitRateService.call(command_event: self)
  end
end
