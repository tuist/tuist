# frozen_string_literal: true

module Secrets
  Error = Class.new(StandardError)
  KeyNotFoundError = Class.new(Error)

  class << self
    def fetch(*args, env: ENV, app_credentials: Rails.application.credentials)
      if Environment.self_hosted? || Environment.use_env_variables?
        key = "TUIST_#{args.join("_").upcase}"
        env.to_h.fetch(key, nil)
      else
        value = app_credentials.dig(*args)
        if value.blank?
          raise KeyNotFoundError, "The key #{args.map(&:to_s).join(".")} was not found in the app credentials"
        end

        value
      end
    end
  end
end
