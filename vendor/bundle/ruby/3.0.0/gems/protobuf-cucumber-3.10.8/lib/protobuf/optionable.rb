module Protobuf
  module Optionable
    module ClassMethods
      def get_option(name)
        name = name.to_s
        option = optionable_descriptor_class.get_field(name, true)
        fail ArgumentError, "invalid option=#{name}" unless option
        unless option.fully_qualified_name.to_s == name
          # Eventually we'll deprecate the use of simple names of fields completely, but for now make sure people
          # are accessing options correctly. We allow simple names in other places for backwards compatibility.
          fail ArgumentError, "must access option using its fully qualified name: #{option.fully_qualified_name.inspect}"
        end
        value =
          if @_optionable_options.try(:key?, name)
            @_optionable_options[name]
          else
            option.default_value
          end
        if option.type_class < ::Protobuf::Message
          option.type_class.new(value)
        else
          value
        end
      end

      def get_option!(name)
        get_option(name) if @_optionable_options.try(:key?, name.to_s)
      end

      private

      def set_option(name, value = true)
        @_optionable_options ||= {}
        @_optionable_options[name.to_s] = value
      end
    end

    def get_option(name)
      self.class.get_option(name)
    end

    def get_option!(name)
      self.class.get_option!(name)
    end

    def self.inject(base_class, extend_class = true, &block)
      unless block_given?
        fail ArgumentError, 'missing option class block (e.g: ::Google::Protobuf::MessageOptions)'
      end
      if extend_class
        # Check if optionable_descriptor_class is already defined and short circuit if so.
        # File options are injected per module, and since a module can be defined more than once,
        # we will get a warning if we try to define optionable_descriptor_class twice.
        if base_class.respond_to?(:optionable_descriptor_class)
          # Don't define optionable_descriptor_class twice
          return  if base_class.optionable_descriptor_class == block.call

          fail 'A class is being defined with two different descriptor classes, something is very wrong'
        end

        base_class.extend(ClassMethods)
        base_class.__send__(:include, self)
        base_class.define_singleton_method(:optionable_descriptor_class, block)
      else
        base_class.__send__(:include, ClassMethods)
        base_class.module_eval { define_method(:optionable_descriptor_class, block) }
      end
    end
  end
end
