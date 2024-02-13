# typed: ignore
# frozen_string_literal: true

if Environment.production_like_env?
  # Use AppSignal's logger and a STDOUT logger
  console_logger = ActiveSupport::Logger.new($stdout)
  if Environment.tuist_hosted?
    betterstack_logger = Logtail::Logger.create_default_logger(Environment.better_stack_api_key)
    appsignal_logger = ActiveSupport::TaggedLogging.new(Appsignal::Logger.new("rails"))
    Rails.application.config.log_tags = [:request_id]
    Rails.logger = ActiveSupport::BroadcastLogger.new(console_logger, appsignal_logger, betterstack_logger)
  else
    Rails.application.config.log_tags = [:request_id]
    Rails.logger = ActiveSupport::BroadcastLogger.new(console_logger)
  end
end
