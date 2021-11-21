# frozen_string_literal: true

if Rails.env.production?
  Bugsnag.configure do |config|
    config.api_key = Rails.application.credentials.dig(:bugsnag, :api_key)
  end
end
