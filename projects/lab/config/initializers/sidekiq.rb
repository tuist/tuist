# frozen_string_literal: true

if Rails.env.production?
  url = ENV.fetch("REDIS_URL")
  sidekiq_config = { url: url }

  Sidekiq.default_worker_options = { retry: 2 }

  Sidekiq.configure_server do |config|
    config.redis = sidekiq_config
  end

  Sidekiq.configure_client do |config|
    config.redis = sidekiq_config
  end
end
