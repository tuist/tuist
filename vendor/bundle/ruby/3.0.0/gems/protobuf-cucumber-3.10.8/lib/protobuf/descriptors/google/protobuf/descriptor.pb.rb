# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'

module Google
  module Protobuf
    ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

    ##
    # Message Classes
    #
    class FileDescriptorSet < ::Protobuf::Message; end
    class FileDescriptorProto < ::Protobuf::Message; end
    class DescriptorProto < ::Protobuf::Message
      class ExtensionRange < ::Protobuf::Message; end
      class ReservedRange < ::Protobuf::Message; end

    end

    class FieldDescriptorProto < ::Protobuf::Message
      class Type < ::Protobuf::Enum
        define :TYPE_DOUBLE, 1
        define :TYPE_FLOAT, 2
        define :TYPE_INT64, 3
        define :TYPE_UINT64, 4
        define :TYPE_INT32, 5
        define :TYPE_FIXED64, 6
        define :TYPE_FIXED32, 7
        define :TYPE_BOOL, 8
        define :TYPE_STRING, 9
        define :TYPE_GROUP, 10
        define :TYPE_MESSAGE, 11
        define :TYPE_BYTES, 12
        define :TYPE_UINT32, 13
        define :TYPE_ENUM, 14
        define :TYPE_SFIXED32, 15
        define :TYPE_SFIXED64, 16
        define :TYPE_SINT32, 17
        define :TYPE_SINT64, 18
      end

      class Label < ::Protobuf::Enum
        define :LABEL_OPTIONAL, 1
        define :LABEL_REQUIRED, 2
        define :LABEL_REPEATED, 3
      end

    end

    class OneofDescriptorProto < ::Protobuf::Message; end
    class EnumDescriptorProto < ::Protobuf::Message; end
    class EnumValueDescriptorProto < ::Protobuf::Message; end
    class ServiceDescriptorProto < ::Protobuf::Message; end
    class MethodDescriptorProto < ::Protobuf::Message; end
    class FileOptions < ::Protobuf::Message
      class OptimizeMode < ::Protobuf::Enum
        define :SPEED, 1
        define :CODE_SIZE, 2
        define :LITE_RUNTIME, 3
      end

    end

    class MessageOptions < ::Protobuf::Message; end
    class FieldOptions < ::Protobuf::Message
      class CType < ::Protobuf::Enum
        define :STRING, 0
        define :CORD, 1
        define :STRING_PIECE, 2
      end

      class JSType < ::Protobuf::Enum
        define :JS_NORMAL, 0
        define :JS_STRING, 1
        define :JS_NUMBER, 2
      end

    end

    class EnumOptions < ::Protobuf::Message; end
    class EnumValueOptions < ::Protobuf::Message; end
    class ServiceOptions < ::Protobuf::Message; end
    class MethodOptions < ::Protobuf::Message; end
    class UninterpretedOption < ::Protobuf::Message
      class NamePart < ::Protobuf::Message; end

    end

    class SourceCodeInfo < ::Protobuf::Message
      class Location < ::Protobuf::Message; end

    end



    ##
    # File Options
    #
    set_option :java_package, "com.google.protobuf"
    set_option :java_outer_classname, "DescriptorProtos"
    set_option :optimize_for, ::Google::Protobuf::FileOptions::OptimizeMode::SPEED
    set_option :go_package, "descriptor"
    set_option :objc_class_prefix, "GPB"
    set_option :csharp_namespace, "Google.Protobuf.Reflection"


    ##
    # Message Fields
    #
    class FileDescriptorSet
      repeated ::Google::Protobuf::FileDescriptorProto, :file, 1
    end

    class FileDescriptorProto
      optional :string, :name, 1
      optional :string, :package, 2
      repeated :string, :dependency, 3
      repeated :int32, :public_dependency, 10
      repeated :int32, :weak_dependency, 11
      repeated ::Google::Protobuf::DescriptorProto, :message_type, 4
      repeated ::Google::Protobuf::EnumDescriptorProto, :enum_type, 5
      repeated ::Google::Protobuf::ServiceDescriptorProto, :service, 6
      repeated ::Google::Protobuf::FieldDescriptorProto, :extension, 7
      optional ::Google::Protobuf::FileOptions, :options, 8
      optional ::Google::Protobuf::SourceCodeInfo, :source_code_info, 9
      optional :string, :syntax, 12
    end

    class DescriptorProto
      class ExtensionRange
        optional :int32, :start, 1
        optional :int32, :end, 2
      end

      class ReservedRange
        optional :int32, :start, 1
        optional :int32, :end, 2
      end

      optional :string, :name, 1
      repeated ::Google::Protobuf::FieldDescriptorProto, :field, 2
      repeated ::Google::Protobuf::FieldDescriptorProto, :extension, 6
      repeated ::Google::Protobuf::DescriptorProto, :nested_type, 3
      repeated ::Google::Protobuf::EnumDescriptorProto, :enum_type, 4
      repeated ::Google::Protobuf::DescriptorProto::ExtensionRange, :extension_range, 5
      repeated ::Google::Protobuf::OneofDescriptorProto, :oneof_decl, 8
      optional ::Google::Protobuf::MessageOptions, :options, 7
      repeated ::Google::Protobuf::DescriptorProto::ReservedRange, :reserved_range, 9
      repeated :string, :reserved_name, 10
    end

    class FieldDescriptorProto
      optional :string, :name, 1
      optional :int32, :number, 3
      optional ::Google::Protobuf::FieldDescriptorProto::Label, :label, 4
      optional ::Google::Protobuf::FieldDescriptorProto::Type, :type, 5
      optional :string, :type_name, 6
      optional :string, :extendee, 2
      optional :string, :default_value, 7
      optional :int32, :oneof_index, 9
      optional :string, :json_name, 10
      optional ::Google::Protobuf::FieldOptions, :options, 8
    end

    class OneofDescriptorProto
      optional :string, :name, 1
    end

    class EnumDescriptorProto
      optional :string, :name, 1
      repeated ::Google::Protobuf::EnumValueDescriptorProto, :value, 2
      optional ::Google::Protobuf::EnumOptions, :options, 3
    end

    class EnumValueDescriptorProto
      optional :string, :name, 1
      optional :int32, :number, 2
      optional ::Google::Protobuf::EnumValueOptions, :options, 3
    end

    class ServiceDescriptorProto
      optional :string, :name, 1
      repeated ::Google::Protobuf::MethodDescriptorProto, :method, 2
      optional ::Google::Protobuf::ServiceOptions, :options, 3
    end

    class MethodDescriptorProto
      optional :string, :name, 1
      optional :string, :input_type, 2
      optional :string, :output_type, 3
      optional ::Google::Protobuf::MethodOptions, :options, 4
      optional :bool, :client_streaming, 5, :default => false
      optional :bool, :server_streaming, 6, :default => false
    end

    class FileOptions
      optional :string, :java_package, 1
      optional :string, :java_outer_classname, 8
      optional :bool, :java_multiple_files, 10, :default => false
      optional :bool, :java_generate_equals_and_hash, 20, :default => false
      optional :bool, :java_string_check_utf8, 27, :default => false
      optional ::Google::Protobuf::FileOptions::OptimizeMode, :optimize_for, 9, :default => ::Google::Protobuf::FileOptions::OptimizeMode::SPEED
      optional :string, :go_package, 11
      optional :bool, :cc_generic_services, 16, :default => false
      optional :bool, :java_generic_services, 17, :default => false
      optional :bool, :py_generic_services, 18, :default => false
      optional :bool, :deprecated, 23, :default => false
      optional :bool, :cc_enable_arenas, 31, :default => false
      optional :string, :objc_class_prefix, 36
      optional :string, :csharp_namespace, 37
      optional :bool, :javanano_use_deprecated_package, 38
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class MessageOptions
      optional :bool, :message_set_wire_format, 1, :default => false
      optional :bool, :no_standard_descriptor_accessor, 2, :default => false
      optional :bool, :deprecated, 3, :default => false
      optional :bool, :map_entry, 7
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class FieldOptions
      optional ::Google::Protobuf::FieldOptions::CType, :ctype, 1, :default => ::Google::Protobuf::FieldOptions::CType::STRING
      optional :bool, :packed, 2
      optional ::Google::Protobuf::FieldOptions::JSType, :jstype, 6, :default => ::Google::Protobuf::FieldOptions::JSType::JS_NORMAL
      optional :bool, :lazy, 5, :default => false
      optional :bool, :deprecated, 3, :default => false
      optional :bool, :weak, 10, :default => false
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class EnumOptions
      optional :bool, :allow_alias, 2
      optional :bool, :deprecated, 3, :default => false
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class EnumValueOptions
      optional :bool, :deprecated, 1, :default => false
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class ServiceOptions
      optional :bool, :deprecated, 33, :default => false
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class MethodOptions
      optional :bool, :deprecated, 33, :default => false
      repeated ::Google::Protobuf::UninterpretedOption, :uninterpreted_option, 999
      # Extension Fields
      extensions 1000...536870912
    end

    class UninterpretedOption
      class NamePart
        required :string, :name_part, 1
        required :bool, :is_extension, 2
      end

      repeated ::Google::Protobuf::UninterpretedOption::NamePart, :name, 2
      optional :string, :identifier_value, 3
      optional :uint64, :positive_int_value, 4
      optional :int64, :negative_int_value, 5
      optional :double, :double_value, 6
      optional :bytes, :string_value, 7
      optional :string, :aggregate_value, 8
    end

    class SourceCodeInfo
      class Location
        repeated :int32, :path, 1, :packed => true
        repeated :int32, :span, 2, :packed => true
        optional :string, :leading_comments, 3
        optional :string, :trailing_comments, 4
        repeated :string, :leading_detached_comments, 6
      end

      repeated ::Google::Protobuf::SourceCodeInfo::Location, :location, 1
    end

  end

end

