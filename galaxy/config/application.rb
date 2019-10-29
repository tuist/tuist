# frozen_string_literal: true

require_relative 'boot'

%w(
  active_record/railtie
  action_controller/railtie
  action_view/railtie
  action_mailer/railtie
  active_job/railtie
  action_cable/engine
  action_mailbox/engine
  action_text/engine
  rails/test_unit/railtie
  sprockets/railtie
).each do |railtie|
  begin
    require railtie
  # rubocop:disable Lint/HandleExceptions
  rescue LoadError
  end
  # rubocop:enable Lint/HandleExceptions
end

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Galaxy
  class Application < Rails::Application
    config.i18n.load_path += Dir[config.root.join('frontend/components/**/*.yml')]
    config.autoload_paths << config.root.join('frontend/components')
    config.load_defaults(5.2)
    config.filter_parameters << :password
    config.assets.enabled = false
    config.assets.compress = false

    config.generators do |g|
      g.assets(false)
    end
  end
end
