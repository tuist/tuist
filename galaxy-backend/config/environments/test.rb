# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false

  # Assets
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}",
  }

  config.consider_all_requests_local = true

  # Action dispatch
  config.action_dispatch.show_exceptions = false

  # Action controller
  config.action_controller.perform_caching = false
  config.action_controller.allow_forgery_protection = false

  # Active storage
  config.active_storage.service = :test

  # Active support
  config.active_support.deprecation = :stderr
end
