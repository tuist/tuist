# frozen_string_literal: true

require "rails/generators/base"
require "active_support/core_ext/string"

module RubocopRailsConfig
  module Generators
    class UpdateGenerator < Rails::Generators::Base
      desc "Update a .rubocop.yml config file that is reanmed."

      def update_config_file
        if old_gem_name_used?
          gsub_file config_file_path, "rubocop-rails:", "rubocop-rails_config:"
        else
          puts "Your config is up-to-date. Nothing to update."
        end
      end

    private
      # rubocop-rails is renamed to rubocop-rails_config
      def old_gem_name_used?
        File.foreach(config_file_path).grep(/\s+rubocop-rails:/).any?
      end

      def config_file_path
        ".rubocop.yml"
      end
    end
  end
end
