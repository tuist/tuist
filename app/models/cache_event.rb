# frozen_string_literal: true

class CacheEvent < ApplicationRecord
  enum :event_type, { download: 0, upload: 1 }

  belongs_to :project, optional: false
end
