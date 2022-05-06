# frozen_string_literal: true

class CommandEvent < ApplicationRecord
  validates :name, :duration, :client_id, :tuist_version, :swift_version, :macos_version, :command_arguments,
    presence: true

  belongs_to :metadata, polymorphic: true, optional: true, dependent: :destroy
  belongs_to :project, optional: false
end
