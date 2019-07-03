# frozen_string_literal: true

if ENV.key?("SENTRY_DSN")
  Raven.configure do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.sanitize_fields = Rails.application.config.filter_parameters.map(&:to_s)
  end
end
