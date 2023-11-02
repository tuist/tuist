# frozen_string_literal: true

require_relative "boot"
require 'sorbet-runtime'
require "rails/all"
require_relative "../app/lib/environment"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TuistCloud
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults(7.0)
    defaults = config_for(:defaults)
    config.defaults = defaults
    config.secret_key_base = Environment.secret_key_base(defaults: defaults)

    # Autoloading
    config.autoload_once_paths << "#{root}/app/lib/defaults"
    config.autoload_once_paths << "#{root}/app/lib/secrets"
    config.autoload_once_paths << "#{root}/app/lib/environment"
    Rails.autoloaders.main.ignore("#{root}/app/frontend")

    # URLs
    Rails.application.routes.default_url_options[:host] = Environment.app_url
    config.action_controller.default_url_options = { host: Environment.app_url }
    config.action_mailer.default_url_options = { host: Environment.app_url }

    # Que
    config.active_record.schema_format = :sql

    # Initializers
    config.before_initialize do
      require_relative "../app/lib/environment"
      Environment.ensure_configured!
    end
  end
end
