# frozen_string_literal: true

module Environment
  def self.bugsnag_backend_key
    ENV["BUGSNAG_BACKEND_KEY"]
  end
end
