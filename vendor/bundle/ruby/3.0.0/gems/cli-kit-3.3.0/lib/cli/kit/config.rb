require 'cli/kit'
require 'fileutils'

module CLI
  module Kit
    class Config
      XDG_CONFIG_HOME = 'XDG_CONFIG_HOME'

      def initialize(tool_name:)
        @tool_name = tool_name
      end

      # Returns the config corresponding to `name` from the config file
      # `false` is returned if it doesn't exist
      #
      # #### Parameters
      # `section` : the section of the config value you are looking for
      # `name` : the name of the config value you are looking for
      #
      # #### Returns
      # `value` : the value of the config variable (false if none)
      #
      # #### Example Usage
      # `config.get('name.of.config')`
      #
      def get(section, name, default: false)
        all_configs.dig("[#{section}]", name) || default
      end

      # Coalesce and enforce the value of a config to a boolean
      def get_bool(section, name, default: false)
        case get(section, name, default: default).to_s
        when "true"
          true
        when "false"
          false
        else
          raise CLI::Kit::Abort, "Invalid config: #{section}.#{name} is expected to be true or false"
        end
      end

      # Sets the config value in the config file
      #
      # #### Parameters
      # `section` : the section of the config you are setting
      # `name` : the name of the config you are setting
      # `value` : the value of the config you are setting
      #
      # #### Example Usage
      # `config.set('section', 'name.of.config', 'value')`
      #
      def set(section, name, value)
        all_configs["[#{section}]"] ||= {}
        all_configs["[#{section}]"][name] = value.nil? ? nil : value.to_s
        write_config
      end

      # Unsets a config value in the config file
      #
      # #### Parameters
      # `section` : the section of the config you are deleting
      # `name` : the name of the config you are deleting
      #
      # #### Example Usage
      # `config.unset('section', 'name.of.config')`
      #
      def unset(section, name)
        set(section, name, nil)
      end

      # Gets the hash for the entire section
      #
      # #### Parameters
      # `section` : the section of the config you are getting
      #
      # #### Example Usage
      # `config.get_section('section')`
      #
      def get_section(section)
        (all_configs["[#{section}]"] || {}).dup
      end

      # Returns a path from config in expanded form
      # e.g. shopify corresponds to ~/src/shopify, but is expanded to /Users/name/src/shopify
      #
      # #### Example Usage
      # `config.get_path('srcpath', 'shopify')`
      #
      # #### Returns
      # `path` : the expanded path to the corrsponding value
      #
      def get_path(section, name = nil)
        v = get(section, name)
        false == v ? v : File.expand_path(v)
      end

      def to_s
        ini.to_s
      end

      # The path on disk at which the configuration is stored:
      #   `$XDG_CONFIG_HOME/<toolname>/config`
      # if ENV['XDG_CONFIG_HOME'] is not set, we default to ~/.config, e.g.:
      #   ~/.config/tool/config
      #
      def file
        config_home = ENV.fetch(XDG_CONFIG_HOME, '~/.config')
        File.expand_path(File.join(@tool_name, 'config'), config_home)
      end

      private

      def all_configs
        ini.ini
      end

      def ini
        @ini ||= CLI::Kit::Ini
          .new(file, default_section: "[global]", convert_types: false)
          .tap(&:parse)
      end

      def write_config
        all_configs.each do |section, sub_config|
          all_configs[section] = sub_config.reject { |_, value| value.nil? }
          all_configs.delete(section) if all_configs[section].empty?
        end
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, to_s)
      end
    end
  end
end
