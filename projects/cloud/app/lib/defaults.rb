# frozen_string_literal: true

require "environment"

module Defaults
  Error = Class.new(StandardError)
  KeyNotFoundError = Class.new(Error)

  def self.fetch(*args, env: ENV, app_defaults: Rails.application.config.defaults)
    if Environment.use_env_variables?
      key = "TUIST_#{args.join("_").upcase}"
      env.to_h.fetch(key)
    else
      value = app_defaults.dig(*args)
      if value.blank?
        raise KeyNotFoundError, "The key #{args.map(&:to_s).join(".")} was not found in the app defaults"
      end

      value
    end
  end
end
