# frozen_string_literal: true

if Environment.tuist_hosted? && Environment.production_like_env?
  # Use AppSignal's logger and a STDOUT logger
  console_logger = ActiveSupport::Logger.new($stdout)
  appsignal_logger = ActiveSupport::TaggedLogging.new(Appsignal::Logger.new("rails"))
  Rails.application.config.log_tags = [:request_id]
  Rails.logger = ActiveSupport::BroadcastLogger.new(console_logger, appsignal_logger)
end
