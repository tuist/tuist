# frozen_string_literal: true

ViteRuby.env["BASE_URL"] = Rails.application.config.defaults[:urls][:app]

if Rails.env.production?
  ViteRuby.env["BUGSNAG_FRONTEND_API_KEY"] = Rails.application.credentials.bugsnag[:frontend_api_key]
end
