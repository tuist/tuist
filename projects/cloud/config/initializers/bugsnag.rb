# frozen_string_literal: true

if Rails.env.production?
  Bugsnag.configure do |config|
    config.api_key = Rails.application.credentials.bugsnag[:backend_api_key]
  end
end
