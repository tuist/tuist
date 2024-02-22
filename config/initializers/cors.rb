# frozen_string_literal: true
# typed: false

Rails.application.config.middleware.insert_before(0, Rack::Cors) do
  # CLI's HTTP server
  allow do
    origins '*'
    resource 'http://127.0.0.1:4545/auth', headers: :any, methods: [:get]
  end
end
