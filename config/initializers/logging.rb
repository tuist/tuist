# frozen_string_literal: true

if Environment.tuist_hosted? && Environment.production_like_env?
  console_logger = ActiveSupport::Logger.new($stdout)
  appsignal_logger = ActiveSupport::TaggedLogging.new(Appsignal::Logger.new("rails"))
  Rails.logger = console_logger.extend(ActiveSupport::Logger.broadcast(appsignal_logger))
end
