# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
  config.i18n.fallbacks = true
  config.log_formatter = ::Logger::Formatter.new

  # Action Controller
  config.action_controller.perform_caching = true

  # Assets
  config.assets.compile = false

  # Active Storage
  config.active_storage.service = :local

  # Active Job
  config.active_job.queue_adapter = :sidekiq

  # Action Mailer
  config.action_mailer.perform_caching = false

  # Active Support
  config.active_support.deprecation = :notify
  config.active_support.disallowed_deprecation = :log
  config.active_support.disallowed_deprecation_warnings = []

  # Active Record
  config.active_record.dump_schema_after_migration = false

  # Logs
  config.log_level = :info
  config.log_tags = [:request_id]
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Action Mailer
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    authentication: :plain,
    address: Rails.application.credentials.mailgun[:address],
    port: 587,
    domain: Rails.application.credentials.mailgun[:domain],
    user_name: Rails.application.credentials.mailgun[:username],
    password: Rails.application.credentials.mailgun[:password],
  }

  # Stripe
  config.stripe.debug_js = false
end
