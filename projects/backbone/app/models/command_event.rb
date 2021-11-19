# frozen_string_literal: true

class CommandEvent < ApplicationRecord
  validates :name, :duration, :client_id, :tuist_version, :swift_version, :macos_version, presence: true
end
