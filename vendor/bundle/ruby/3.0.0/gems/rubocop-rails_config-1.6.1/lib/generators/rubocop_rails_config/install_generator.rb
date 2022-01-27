# frozen_string_literal: true

require "rails/generators/base"
require "active_support/core_ext/string"

module RubocopRailsConfig
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Creates a .rubocop.yml config file that inherits from the official Ruby on Rails .rubocop.yml."

      def create_config_file
        file_method = config_file_exists? ? :prepend : :create
        send :"#{file_method}_file", config_file_path, config_file_content
      end

    private
      def config_file_exists?
        File.exist?(config_file_path)
      end

      def config_file_path
        ".rubocop.yml"
      end

      def config_file_content
        <<-EOS.strip_heredoc
          inherit_gem:
            rubocop-rails_config:
              - config/rails.yml
        EOS
      end
    end
  end
end
