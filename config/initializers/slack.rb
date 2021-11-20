# frozen_string_literal: true

Slack.configure do |config|
  config.token = Rails.application.credentials.slack[:token]
end
