require "set"

module Protobuf
  class Message
    module Fields

      ACCESSOR_SUFFIXES = ["", "=", "!", "?"].freeze

      def self.extended(other)
        other.extend(ClassMethods)
        ::Protobuf.deprecator.define_deprecated_methods(
          other.singleton_class,
          :get_ext_field_by_name => :get_extension_field,
          :get_ext_field_by_tag => :get_extension_field,
          :get_field_by_name => :get_field,
          :get_field_by_tag => :get_field,
        )
      end

      module ClassMethods
        def inherited(subclass)
          inherit_fields!(subclass)
          subclass.const_set("PROTOBUF_MESSAGE_REQUIRED_FIELD_TAGS", subclass.required_field_tags)
          subclass.const_set("PROTOBUF_MESSAGE_GET_FIELD", subclass.field_store)
          subclass.class_eval <<-RUBY, __FILE__, __LINE__
            def _protobuf_message_field
              PROTOBUF_MESSAGE_GET_FIELD
            end

            def _protobuf_message_unset_required_field_tags
              @_protobuf_message_unset_required_field_tags ||= PROTOBUF_MESSAGE_REQUIRED_FIELD_TAGS.dup
            end
          RUBY
        end

        ##
        # Field Definition Methods
        #

        # Define an optional field.
        #
        def optional(type_class, name, tag, options = {})
          define_field(:optional, type_class, name, tag, options)
        end

        # Define a repeated field.
        #
        def repeated(type_class, name, tag, options = {})
          define_field(:repeated, type_class, name, tag, options)
        end

        # Define a required field.
        #
        def required(type_class, name, tag, options = {})
          required_field_tags << tag
          define_field(:required, type_class, name, tag, options)
        end

        # Define a map field.
        #
        def map(key_type_class, value_type_class, name, tag, options = {})
          # manufacture a message that represents the map entry, used for
          # serialization and deserialization
          entry_type = Class.new(::Protobuf::Message) do
            set_option :map_entry, true
            optional key_type_class, :key, 1
            optional value_type_class, :value, 2
          end
          define_field(:repeated, entry_type, name, tag, options)
        end

        # Define an extension range.
        #
        def extensions(range)
          extension_ranges << range
        end

        ##
        # Field Access Methods
        #
        def all_fields
          @all_fields ||= field_store.values.uniq.sort_by(&:tag)
        end

        def extension_fields
          @extension_fields ||= all_fields.select(&:extension?)
        end

        def extension_ranges
          @extension_ranges ||= []
        end

        def required_field_tags
          @required_field_tags ||= []
        end

        def extension_tag?(tag)
          tag.respond_to?(:to_i) && get_extension_field(tag).present?
        end

        def field_store
          @field_store ||= {}
        end

        def fields
          @fields ||= all_fields.reject(&:extension?)
        end

        def field_tag?(tag, allow_extension = false)
          tag.respond_to?(:to_i) && get_field(tag, allow_extension).present?
        end

        def get_extension_field(name_or_tag)
          field = field_store[name_or_tag]
          field if field.try(:extension?) { false }
        end

        def get_field(name_or_tag, allow_extension = false)
          field = field_store[name_or_tag]

          if field && (allow_extension || !field.extension?)
            field
          else
            nil
          end
        end

        def define_field(rule, type_class, fully_qualified_field_name, tag, options)
          raise_if_tag_collision(tag, fully_qualified_field_name)
          raise_if_name_collision(fully_qualified_field_name)

          # Determine appropirate accessor for fields depending on name collisions via extensions:

          # Case 1: Base field = "string_field" and no extensions of the same name
          # Result:
          #   message.string_field #=> @values["string_field"]
          #   message[:string_field] #=> @values["string_field"]
          #   message['string_field'] #=> @values["string_field"]

          # Case 2: Base field = "string_field" and extension 1 = ".my_package.string_field", extension N = ".package_N.string_field"...
          # Result:
          #   message.string_field #=> @values["string_field"]
          #   message[:string_field] #=> @values["string_field"]
          #   message['string_field'] #=> @values["string_field"]
          #   message[:'.my_package.string_field'] #=> @values[".my_package.string_field"]
          #   message['.my_package.string_field']  #=> @values[".my_package.string_field"]

          # Case 3: No base field, extension 1 = ".my_package.string_field", extension 2 = ".other_package.string_field", extension N...
          # Result:
          #   message.string_field #=> raise NoMethodError (no simple accessor allowed)
          #   message[:string_field] #=> raise NoMethodError (no simple accessor allowed)
          #   message['string_field'] #=> raise NoMethodError (no simple accessor allowed)
          #   message[:'.my_package.string_field'] #=> @values[".my_package.string_field"]
          #   message['.my_package.string_field']  #=> @values[".my_package.string_field"]
          #   message[:'.other_package.string_field'] #=> @values[".other_package.string_field"]
          #   message['.other_package.string_field']  #=> @values[".other_package.string_field"]

          # Case 4: No base field, extension = ".my_package.string_field", no other extensions
          # Result:
          #   message.string_field #=> @values[".my_package.string_field"]
          #   message[:string_field] #=> @values[".my_package.string_field"]
          #   message['string_field'] #=> @values[".my_package.string_field"]
          #   message[:'.my_package.string_field'] #=> @values[".my_package.string_field"]
          #   message[:'.my_package.string_field'] #=> @values[".my_package.string_field"]

          simple_name =
            if options[:extension]
              base_name = fully_qualified_field_name.to_s.split('.').last.to_sym
              if field_store[base_name]
                # Case 3
                if field_store[base_name].extension?
                  remove_existing_accessors(base_name)
                end
                nil
              # Case 4
              else
                base_name
              end
            else
              # Case 1
              fully_qualified_field_name
            end

          field = ::Protobuf::Field.build(self, rule, type_class, fully_qualified_field_name,
                                          tag, simple_name, options)
          field_store[tag] = field
          field_store[fully_qualified_field_name.to_sym] = field
          field_store[fully_qualified_field_name.to_s] = field
          if simple_name && simple_name != fully_qualified_field_name
            field_store[simple_name.to_sym] = field
            field_store[simple_name.to_s] = field
          end
          # defining a new field for the message will cause cached @all_fields, @extension_fields,
          # and @fields to be incorrect; reset them
          @all_fields = @extension_fields = @fields = nil
        end

        def remove_existing_accessors(accessor)
          field_store.delete(accessor.to_sym).try(:fully_qualified_name_only!)
          field_store.delete(accessor.to_s)
          ACCESSOR_SUFFIXES.each do |modifier|
            begin
              remove_method("#{accessor}#{modifier}")
            # rubocop: disable Lint/HandleExceptions
            rescue NameError
              # Do not remove the method
            end
          end
        end

        def raise_if_tag_collision(tag, field_name)
          if get_field(tag, true)
            fail TagCollisionError, %(Field number #{tag} has already been used in "#{name}" by field "#{field_name}".)
          end
        end

        def raise_if_name_collision(field_name)
          if get_field(field_name, true)
            fail DuplicateFieldNameError, %(Field name #{field_name} has already been used in "#{name}".)
          end
        end

        def inherit_fields!(subclass)
          instance_variables.each do |iv|
            subclass.instance_variable_set(iv, instance_variable_get(iv))
          end
        end
        private :inherit_fields!

      end
    end
  end
end
