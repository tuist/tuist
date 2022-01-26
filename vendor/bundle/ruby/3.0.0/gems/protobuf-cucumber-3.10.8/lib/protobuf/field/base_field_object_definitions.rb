module Protobuf
  module Field
    module BaseFieldObjectDefinitions

      class ToHashValueToMessageHashWithStringKey
        def initialize(selph)
          @selph = selph
          @name = selph.name.to_s
        end

        def call(values, result)
          result[@name] = @selph.value_from_values(values).to_hash_value
        end
      end

      class BaseToMessageHashWithStringKey
        def initialize(selph)
          @selph = selph
          @name = selph.name.to_s
        end

        def call(values, result)
          result[@name] = @selph.value_from_values(values)
        end
      end

      class ToHashValueToMessageHash
        def initialize(selph)
          @selph = selph
          @name = selph.name.to_sym
        end

        def call(values, result)
          result[@name] = @selph.value_from_values(values).to_hash_value
        end
      end

      class BaseToMessageHash
        def initialize(selph)
          @selph = selph
          @name = selph.name.to_sym
        end

        def call(values, result)
          result[@name] = @selph.value_from_values(values)
        end
      end

      class RepeatedPackedEncodeToStream
        def initialize(selph)
          @selph = selph
          @tag_encoded = selph.tag_encoded
        end

        def call(value, stream)
          packed_value = value.map { |val| @selph.encode(val) }.join
          stream << @tag_encoded << "#{::Protobuf::Field::VarintField.encode(packed_value.size)}#{packed_value}"
        end
      end

      class BytesEncodeToStream
        def initialize(selph)
          @selph = selph
          @tag_encoded = selph.tag_encoded
        end

        def call(value, stream)
          value = value.encode if value.is_a?(::Protobuf::Message)
          byte_size = ::Protobuf::Field::VarintField.encode(value.bytesize)

          stream << @tag_encoded << byte_size << value
        end
      end

      class StringEncodeToStream
        def initialize(selph)
          @selph = selph
          @tag_encoded = selph.tag_encoded
        end

        def call(value, stream)
          new_value = "" + value
          if new_value.encoding != ::Protobuf::Field::StringField::ENCODING
            new_value.encode!(::Protobuf::Field::StringField::ENCODING, :invalid => :replace, :undef => :replace, :replace => "")
          end

          stream << @tag_encoded << ::Protobuf::Field::VarintField.encode(new_value.bytesize) << new_value
        end
      end

      class BaseEncodeToStream
        def initialize(selph)
          @selph = selph
          @tag_encoded = selph.tag_encoded
        end

        def call(value, stream)
          stream << @tag_encoded << @selph.encode(value)
        end
      end

      class RepeatedNotPackedEncodeToStream
        def initialize(selph)
          @selph = selph
          @tag_encoded = selph.tag_encoded
        end

        def call(value, stream)
          value.each do |val|
            stream << @tag_encoded << @selph.encode(val)
          end
        end
      end

      class BaseSetMethod
        def initialize(selph)
          @selph = selph
          @name = selph.name
        end

        def call(message_instance, bytes)
          message_instance.set_field(@name, @selph.decode(bytes), true, @selph)
        end
      end

      class MapSetMethod
        def initialize(selph)
          @selph = selph
          @name = selph.name
        end

        def call(message_instance, bytes)
          hash = message_instance[@name]
          entry = @selph.decode(bytes)
          # decoded value could be nil for an
          # enum value that is not recognized
          hash[entry.key] = entry.value unless entry.value.nil?
          hash[entry.key]
        end
      end

      class RepeatedNotPackedSetMethod
        def initialize(selph)
          @selph = selph
          @name = selph.name
        end

        def call(message_instance, bytes)
          message_instance[@name] << @selph.decode(bytes)
        end
      end

      class RepeatedPackedSetMethod
        def initialize(selph)
          @selph = selph
          @name = selph.name
          @wire_type = selph.wire_type
        end

        def call(message_instance, bytes)
          array = message_instance[@name]
          stream = ::StringIO.new(bytes)

          if @wire_type == ::Protobuf::WireType::VARINT
            array << @selph.decode(Varint.decode(stream)) until stream.eof?
          elsif @wire_type == ::Protobuf::WireType::FIXED64
            array << @selph.decode(stream.read(8)) until stream.eof?
          elsif @wire_type == ::Protobuf::WireType::FIXED32
            array << @selph.decode(stream.read(4)) until stream.eof?
          end
        end
      end

      class RequiredMapSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, _ignore_nil_for_repeated, message_instance)
          unless value.is_a?(Hash)
            fail TypeError, <<-TYPE_ERROR
                    Expected map value
                    Got '#{value.class}' for map protobuf field #{@selph.name}
            TYPE_ERROR
          end

          if value.empty?
            values.delete(@fully_qualified_name)
            message_instance._protobuf_message_unset_required_field_tags << @tag
          else
            message_instance._protobuf_message_unset_required_field_tags.delete(@tag)
            values[@fully_qualified_name] ||= ::Protobuf::Field::FieldHash.new(@selph)
            values[@fully_qualified_name].replace(value)
          end
        end
      end

      class MapSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, _ignore_nil_for_repeated, _message_instance)
          unless value.is_a?(Hash)
            fail TypeError, <<-TYPE_ERROR
                    Expected map value
                    Got '#{value.class}' for map protobuf field #{@selph.name}
            TYPE_ERROR
          end

          if value.empty?
            values.delete(@fully_qualified_name)
          else
            values[@fully_qualified_name] ||= ::Protobuf::Field::FieldHash.new(@selph)
            values[@fully_qualified_name].replace(value)
          end
        end
      end

      class RequiredRepeatedSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, ignore_nil_for_repeated, message_instance)
          if value.nil? && ignore_nil_for_repeated
            ::Protobuf.deprecator.deprecation_warning("['#{@fully_qualified_name}']=nil", "use an empty array instead of nil")
            return
          end

          unless value.is_a?(Array)
            fail TypeError, <<-TYPE_ERROR
                  Expected repeated value of type '#{@selph.type_class}'
                  Got '#{value.class}' for repeated protobuf field #{@selph.name}
            TYPE_ERROR
          end

          value = value.compact

          if value.empty?
            values.delete(@fully_qualified_name)
            message_instance._protobuf_message_unset_required_field_tags << @tag
          else
            message_instance._protobuf_message_unset_required_field_tags.delete(@tag)
            values[@fully_qualified_name] ||= ::Protobuf::Field::FieldArray.new(@selph)
            values[@fully_qualified_name].replace(value)
          end
        end
      end

      class RepeatedSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, ignore_nil_for_repeated, _message_instance)
          if value.nil? && ignore_nil_for_repeated
            ::Protobuf.deprecator.deprecation_warning("['#{@fully_qualified_name}']=nil", "use an empty array instead of nil")
            return
          end

          unless value.is_a?(Array)
            fail TypeError, <<-TYPE_ERROR
                  Expected repeated value of type '#{@selph.type_class}'
                  Got '#{value.class}' for repeated protobuf field #{@selph.name}
            TYPE_ERROR
          end

          value = value.compact

          if value.empty?
            values.delete(@fully_qualified_name)
          else
            values[@fully_qualified_name] ||= ::Protobuf::Field::FieldArray.new(@selph)
            values[@fully_qualified_name].replace(value)
          end
        end
      end

      class RequiredStringSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, _ignore_nil_for_repeated, message_instance)
          if value
            message_instance._protobuf_message_unset_required_field_tags.delete(@tag)
            values[@fully_qualified_name] = if value.is_a?(String)
                                              value
                                            else
                                              @selph.coerce!(value)
                                            end
          else
            values.delete(@fully_qualified_name)
            message_instance._protobuf_message_unset_required_field_tags << @tag
          end
        end
      end

      class StringSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, _ignore_nil_for_repeated, _message_instance)
          if value
            values[@fully_qualified_name] = if value.is_a?(String)
                                              value
                                            else
                                              @selph.coerce!(value)
                                            end
          else
            values.delete(@fully_qualified_name)
          end
        end
      end

      class RequiredBaseSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, _ignore_nil_for_repeated, message_instance)
          if value.nil?
            values.delete(@fully_qualified_name)
            message_instance._protobuf_message_unset_required_field_tags << @tag
          else
            message_instance._protobuf_message_unset_required_field_tags.delete(@tag)
            values[@fully_qualified_name] = @selph.coerce!(value)
          end
        end
      end

      class BaseSetField
        def initialize(selph)
          @selph = selph
          @tag = selph.tag
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values, value, _ignore_nil_for_repeated, _message_instance)
          if value.nil?
            values.delete(@fully_qualified_name)
          else
            values[@fully_qualified_name] = @selph.coerce!(value)
          end
        end
      end

      class BaseFieldAndPresentPredicate
        def initialize(selph)
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values[@fully_qualified_name].present?
        end
      end

      class BoolFieldAndPresentPredicate
        BOOL_VALUES = [true, false].freeze

        def initialize(selph)
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          BOOL_VALUES.include?(values[@fully_qualified_name])
        end
      end

      class BaseFieldPredicate
        def initialize(selph)
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values.key?(@fully_qualified_name)
        end
      end

      class RepeatedFieldPredicate
        def initialize(selph)
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values.key?(@fully_qualified_name) &&
            values[@fully_qualified_name].present?
        end
      end

      class BoolFieldValueFromValues
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values.fetch(@fully_qualified_name) { @selph.default_value }
        end
      end

      class BoolFieldValueFromValuesForSerialization
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values.fetch(@fully_qualified_name) { @selph.default_value }
        end
      end

      class BaseFieldValueFromValues
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values[@fully_qualified_name] || @selph.default_value
        end
      end

      class BaseFieldValueFromValuesForSerialization
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values[@fully_qualified_name] || @selph.default_value
        end
      end

      class MapValueFromValues
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values[@fully_qualified_name] ||= ::Protobuf::Field::FieldHash.new(@selph)
        end
      end

      class MapValueFromValuesForSerialization
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
          @type_class = selph.type_class
        end

        def call(values)
          value = values[@fully_qualified_name] ||= ::Protobuf::Field::FieldHash.new(@selph)

          array = []
          value.each do |k, v|
            array << @type_class.new(:key => k, :value => v)
          end

          array
        end
      end

      class RepeatedFieldValueFromValues
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values[@fully_qualified_name] ||= ::Protobuf::Field::FieldArray.new(@selph)
        end
      end

      class RepeatedFieldValueFromValuesForSerialization
        def initialize(selph)
          @selph = selph
          @fully_qualified_name = selph.fully_qualified_name
        end

        def call(values)
          values[@fully_qualified_name] ||= ::Protobuf::Field::FieldArray.new(@selph)
        end
      end
    end
  end
end
