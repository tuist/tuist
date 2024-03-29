# frozen_string_literal: true

require_relative "boot"
require 'sorbet-runtime'
require "rails/all"
require_relative "../app/lib/environment"
require_relative "../lib/middleware/response_request_id_middleware"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TuistCloud
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults(7.0)

    defaults = config_for(:defaults)
    config.defaults = defaults

    # Autoloading
    config.autoload_once_paths << "#{root}/app/lib/defaults"
    config.autoload_once_paths << "#{root}/app/lib/secrets"
    config.autoload_once_paths << "#{root}/app/lib/environment"
    Rails.autoloaders.main.ignore("#{root}/app/frontend")

    # URLs
    Rails.application.routes.default_url_options[:host] = Environment.app_url(defaults: config.defaults)
    config.action_controller.default_url_options = { host: Environment.app_url(defaults: config.defaults) }
    config.action_mailer.default_url_options = { host: Environment.app_url(defaults: config.defaults) }

    # Que
    config.active_record.schema_format = :sql

    # Middlewarees
    config.middleware.insert_after(ActionDispatch::RequestId, ResponseRequestIdMiddleware)

    # Initializers
    config.before_initialize do
      require_relative "../app/lib/environment"
      Environment.ensure_configured!
    end
  end
end
