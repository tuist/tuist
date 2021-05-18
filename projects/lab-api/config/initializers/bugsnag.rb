# frozen_string_literal: true

unless Rails.env.test? || Rails.env.development? || Environment.bugsnag_backend_key.blank?
  Bugsnag.configure do |config|
    config.api_key = Environment.bugsnag_backend_key
  end
end
