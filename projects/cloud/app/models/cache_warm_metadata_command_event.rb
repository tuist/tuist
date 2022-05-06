# frozen_string_literal: true

class CacheWarmMetadataCommandEvent < ApplicationRecord
  has_one :command_event, as: :metadata, required: true
end
