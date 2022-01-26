# frozen_string_literal: true

require "active_support"
require "active_support/i18n_railtie"

module ActiveSupport
  class Railtie < Rails::Railtie # :nodoc:
    config.active_support = ActiveSupport::OrderedOptions.new

    config.eager_load_namespaces << ActiveSupport

    initializer "active_support.set_authenticated_message_encryption" do |app|
      config.after_initialize do
        unless app.config.active_support.use_authenticated_message_encryption.nil?
          ActiveSupport::MessageEncryptor.use_authenticated_message_encryption =
            app.config.active_support.use_authenticated_message_encryption
        end
      end
    end

    initializer "active_support.reset_all_current_attributes_instances" do |app|
      app.reloader.before_class_unload { ActiveSupport::CurrentAttributes.clear_all }
      app.executor.to_run              { ActiveSupport::CurrentAttributes.reset_all }
      app.executor.to_complete         { ActiveSupport::CurrentAttributes.reset_all }

      ActiveSupport.on_load(:active_support_test_case) do
        require "active_support/current_attributes/test_helper"
        include ActiveSupport::CurrentAttributes::TestHelper
      end
    end

    initializer "active_support.deprecation_behavior" do |app|
      if deprecation = app.config.active_support.deprecation
        ActiveSupport::Deprecation.behavior = deprecation
      end

      if disallowed_deprecation = app.config.active_support.disallowed_deprecation
        ActiveSupport::Deprecation.disallowed_behavior = disallowed_deprecation
      end

      if disallowed_warnings = app.config.active_support.disallowed_deprecation_warnings
        ActiveSupport::Deprecation.disallowed_warnings = disallowed_warnings
      end
    end

    # Sets the default value for Time.zone
    # If assigned value cannot be matched to a TimeZone, an exception will be raised.
    initializer "active_support.initialize_time_zone" do |app|
      begin
        TZInfo::DataSource.get
      rescue TZInfo::DataSourceNotFound => e
        raise e.exception "tzinfo-data is not present. Please add gem 'tzinfo-data' to your Gemfile and run bundle install"
      end
      require "active_support/core_ext/time/zones"
      Time.zone_default = Time.find_zone!(app.config.time_zone)
    end

    # Sets the default week start
    # If assigned value is not a valid day symbol (e.g. :sunday, :monday, ...), an exception will be raised.
    initializer "active_support.initialize_beginning_of_week" do |app|
      require "active_support/core_ext/date/calculations"
      beginning_of_week_default = Date.find_beginning_of_week!(app.config.beginning_of_week)

      Date.beginning_of_week_default = beginning_of_week_default
    end

    initializer "active_support.require_master_key" do |app|
      if app.config.respond_to?(:require_master_key) && app.config.require_master_key
        begin
          app.credentials.key
        rescue ActiveSupport::EncryptedFile::MissingKeyError => error
          $stderr.puts error.message
          exit 1
        end
      end
    end

    initializer "active_support.set_configs" do |app|
      app.config.active_support.each do |k, v|
        k = "#{k}="
        ActiveSupport.public_send(k, v) if ActiveSupport.respond_to? k
      end
    end

    initializer "active_support.set_hash_digest_class" do |app|
      config.after_initialize do
        if app.config.active_support.use_sha1_digests
          ActiveSupport::Deprecation.warn(<<-MSG.squish)
            config.active_support.use_sha1_digests is deprecated and will
            be removed from Rails 6.2. Use
            config.active_support.hash_digest_class = ::Digest::SHA1 instead.
          MSG
          ActiveSupport::Digest.hash_digest_class = ::Digest::SHA1
        end

        if klass = app.config.active_support.hash_digest_class
          ActiveSupport::Digest.hash_digest_class = klass
        end
      end
    end
  end
end
