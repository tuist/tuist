require 'active_support/deprecation'

module Protobuf
  if ::ActiveSupport::Deprecation.is_a?(Class)
    class DeprecationBase < ::ActiveSupport::Deprecation
      def deprecate_methods(*args)
        deprecation_options = { :deprecator => self }

        if args.last.is_a?(Hash)
          args.last.merge!(deprecation_options)
        else
          args.push(deprecation_options)
        end

        super
      end

      def deprecation_warning(deprecated_method_name, message = nil, caller_backtrace = nil)
        # This ensures ActiveSupport::Deprecation doesn't look for the caller, which is very costly.
        super(deprecated_method_name, message, caller_backtrace) unless ENV.key?('PB_IGNORE_DEPRECATIONS')
      end
    end

    class Deprecation < DeprecationBase
      def define_deprecated_methods(target_module, method_hash)
        target_module.module_eval do
          method_hash.each do |old_method, new_method|
            alias_method old_method, new_method
          end
        end

        deprecate_methods(target_module, method_hash)
      end
    end

    class FieldDeprecation < DeprecationBase
      # this is a convenience deprecator for deprecated proto fields

      def deprecate_method(target_module, method_name)
        deprecate_methods(target_module, method_name => target_module)
      end

      private

      def deprecated_method_warning(method_name, target_module)
        "#{target_module.name}##{method_name} field usage is deprecated"
      end
    end
  else
    # TODO: remove this clause when Rails < 4 support is no longer needed
    deprecator = ::ActiveSupport::Deprecation.clone
    deprecator.instance_eval do
      def new(deprecation_horizon = nil, *)
        self.deprecation_horizon = deprecation_horizon if deprecation_horizon
        self
      end
    end
    Deprecation = deprecator.clone
    FieldDeprecation = deprecator.clone

    Deprecation.instance_eval do
      def define_deprecated_methods(target_module, method_hash)
        target_module.module_eval do
          method_hash.each do |old_method, new_method|
            alias_method old_method, new_method
          end
        end

        deprecate_methods(target_module, method_hash)
      end
    end

    FieldDeprecation.instance_eval do
      def deprecate_method(target_module, method_name)
        deprecate_methods(target_module, method_name => target_module)
      end

      private

      def deprecated_method_warning(method_name, target_module)
        "#{target_module.name}##{method_name} field usage is deprecated"
      end
    end
  end

  def self.deprecator
    @deprecator ||= Deprecation.new('4.0', to_s).tap do |deprecation|
      deprecation.silenced = ENV.key?('PB_IGNORE_DEPRECATIONS')
      deprecation.behavior = :stderr
    end
  end

  def self.field_deprecator
    @field_deprecator ||= FieldDeprecation.new.tap do |deprecation|
      deprecation.silenced = ENV.key?('PB_IGNORE_DEPRECATIONS')
      deprecation.behavior = :stderr
    end
  end

  # Print Deprecation Warnings
  #
  # Default: true
  #
  # Simple boolean to define whether we want field deprecation warnings to
  # be printed to stderr or not. The rpc_server has an option to set this value
  # explicitly, or you can turn this option off by setting
  # ENV['PB_IGNORE_DEPRECATIONS'] to a non-empty value.
  #
  # The rpc_server option will override the ENV setting.
  def self.print_deprecation_warnings?
    !field_deprecator.silenced
  end

  def self.print_deprecation_warnings=(value)
    field_deprecator.silenced = !value
  end
end
