# frozen_string_literal: true

require_relative 'boot'

%w(
  active_record/railtie
  action_controller/railtie
  action_view/railtie
  active_job/railtie
  rails/test_unit/railtie
  sprockets/railtie
).each do |railtie|
  begin
    require railtie
  rescue LoadError
  end
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
  end
end
