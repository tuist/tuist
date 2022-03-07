# frozen_string_literal: true

module Secrets
  Error = Class.new(StandardError)
  KeyNotFoundError = Class.new(Error)

  def self.fetch(*args, env: ENV, app_credentials: Rails.application.credentials)
    if Environment.use_env_variables?
      key = "TUIST_#{args.join("_").upcase}"
      env.to_h.fetch(key)
    else
      value = app_credentials.dig(*args)
      if value.blank?
        raise KeyNotFoundError, "The key #{args.map(&:to_s).join(".")} was not found in the app credentials"
      end

      value
    end
  end
end
