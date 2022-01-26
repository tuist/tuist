# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'
require 'protobuf/rpc/service'


##
# Imports
#
require 'google/protobuf/descriptor.pb'

module Protobuf_unittest
  ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

  ##
  # Enum Classes
  #
  class MethodOpt1 < ::Protobuf::Enum
    define :METHODOPT1_VAL1, 1
    define :METHODOPT1_VAL2, 2
  end

  class AggregateEnum < ::Protobuf::Enum
    set_option :".protobuf_unittest.enumopt", { :s => "EnumAnnotation" }

    define :VALUE, 1
  end


  ##
  # Message Classes
  #
  class TestMessageWithCustomOptions < ::Protobuf::Message
    class AnEnum < ::Protobuf::Enum
      set_option :".protobuf_unittest.enum_opt1", -789

      define :ANENUM_VAL1, 1
      define :ANENUM_VAL2, 2
    end

  end

  class CustomOptionFooRequest < ::Protobuf::Message; end
  class CustomOptionFooResponse < ::Protobuf::Message; end
  class CustomOptionFooClientMessage < ::Protobuf::Message; end
  class CustomOptionFooServerMessage < ::Protobuf::Message; end
  class DummyMessageContainingEnum < ::Protobuf::Message
    class TestEnumType < ::Protobuf::Enum
      define :TEST_OPTION_ENUM_TYPE1, 22
      define :TEST_OPTION_ENUM_TYPE2, -23
    end

  end

  class DummyMessageInvalidAsOptionType < ::Protobuf::Message; end
  class CustomOptionMinIntegerValues < ::Protobuf::Message; end
  class CustomOptionMaxIntegerValues < ::Protobuf::Message; end
  class CustomOptionOtherValues < ::Protobuf::Message; end
  class SettingRealsFromPositiveInts < ::Protobuf::Message; end
  class SettingRealsFromNegativeInts < ::Protobuf::Message; end
  class ComplexOptionType1 < ::Protobuf::Message; end
  class ComplexOptionType2 < ::Protobuf::Message
    class ComplexOptionType4 < ::Protobuf::Message; end

  end

  class ComplexOptionType3 < ::Protobuf::Message; end
  class VariousComplexOptions < ::Protobuf::Message; end
  class AggregateMessageSet < ::Protobuf::Message; end
  class AggregateMessageSetElement < ::Protobuf::Message; end
  class Aggregate < ::Protobuf::Message; end
  class AggregateMessage < ::Protobuf::Message; end
  class NestedOptionType < ::Protobuf::Message
    class NestedEnum < ::Protobuf::Enum
      set_option :".protobuf_unittest.enum_opt1", 1003

      define :NESTED_ENUM_VALUE, 1
    end

    class NestedMessage < ::Protobuf::Message; end

  end

  class OldOptionType < ::Protobuf::Message
    class TestEnum < ::Protobuf::Enum
      define :OLD_VALUE, 0
    end

  end

  class NewOptionType < ::Protobuf::Message
    class TestEnum < ::Protobuf::Enum
      define :OLD_VALUE, 0
      define :NEW_VALUE, 1
    end

  end

  class TestMessageWithRequiredEnumOption < ::Protobuf::Message; end


  ##
  # File Options
  #
  set_option :cc_generic_services, true
  set_option :java_generic_services, true
  set_option :py_generic_services, true
  set_option :".protobuf_unittest.file_opt1", 9876543210
  set_option :".protobuf_unittest.fileopt", { :i => 100, :s => "FileAnnotation", :sub => { :s => "NestedFileAnnotation" }, :file => { :".protobuf_unittest.fileopt" => { :s => "FileExtensionAnnotation" } }, :mset => { :".protobuf_unittest.AggregateMessageSetElement.message_set_extension" => { :s => "EmbeddedMessageSetElement" } } }


  ##
  # Message Fields
  #
  class TestMessageWithCustomOptions
    # Message Options
    set_option :message_set_wire_format, false
    set_option :".protobuf_unittest.message_opt1", -56

    optional :string, :field1, 1, :ctype => ::Google::Protobuf::FieldOptions::CType::CORD, :".protobuf_unittest.field_opt1" => 8765432109
  end

  class CustomOptionMinIntegerValues
    # Message Options
    set_option :".protobuf_unittest.sfixed64_opt", -9223372036854775808
    set_option :".protobuf_unittest.sfixed32_opt", -2147483648
    set_option :".protobuf_unittest.fixed64_opt", 0
    set_option :".protobuf_unittest.fixed32_opt", 0
    set_option :".protobuf_unittest.sint64_opt", -9223372036854775808
    set_option :".protobuf_unittest.sint32_opt", -2147483648
    set_option :".protobuf_unittest.uint64_opt", 0
    set_option :".protobuf_unittest.uint32_opt", 0
    set_option :".protobuf_unittest.int64_opt", -9223372036854775808
    set_option :".protobuf_unittest.int32_opt", -2147483648
    set_option :".protobuf_unittest.bool_opt", false

  end

  class CustomOptionMaxIntegerValues
    # Message Options
    set_option :".protobuf_unittest.sfixed64_opt", 9223372036854775807
    set_option :".protobuf_unittest.sfixed32_opt", 2147483647
    set_option :".protobuf_unittest.fixed64_opt", 18446744073709551615
    set_option :".protobuf_unittest.fixed32_opt", 4294967295
    set_option :".protobuf_unittest.sint64_opt", 9223372036854775807
    set_option :".protobuf_unittest.sint32_opt", 2147483647
    set_option :".protobuf_unittest.uint64_opt", 18446744073709551615
    set_option :".protobuf_unittest.uint32_opt", 4294967295
    set_option :".protobuf_unittest.int64_opt", 9223372036854775807
    set_option :".protobuf_unittest.int32_opt", 2147483647
    set_option :".protobuf_unittest.bool_opt", true

  end

  class CustomOptionOtherValues
    # Message Options
    set_option :".protobuf_unittest.enum_opt", ::Protobuf_unittest::DummyMessageContainingEnum::TestEnumType::TEST_OPTION_ENUM_TYPE2
    set_option :".protobuf_unittest.bytes_opt", "Hello\x00World"
    set_option :".protobuf_unittest.string_opt", "Hello, \"World\""
    set_option :".protobuf_unittest.double_opt", 1.2345678901234567
    set_option :".protobuf_unittest.float_opt", 12.34567928314209
    set_option :".protobuf_unittest.int32_opt", -100

  end

  class SettingRealsFromPositiveInts
    # Message Options
    set_option :".protobuf_unittest.double_opt", 154.0
    set_option :".protobuf_unittest.float_opt", 12.0

  end

  class SettingRealsFromNegativeInts
    # Message Options
    set_option :".protobuf_unittest.double_opt", -154.0
    set_option :".protobuf_unittest.float_opt", -12.0

  end

  class ComplexOptionType1
    optional :int32, :foo, 1
    optional :int32, :foo2, 2
    optional :int32, :foo3, 3
    repeated :int32, :foo4, 4
    # Extension Fields
    extensions 100...536870912
    optional :int32, :".protobuf_unittest.quux", 7663707, :extension => true
    optional ::Protobuf_unittest::ComplexOptionType3, :".protobuf_unittest.corge", 7663442, :extension => true
  end

  class ComplexOptionType2
    class ComplexOptionType4
      optional :int32, :waldo, 1
    end

    optional ::Protobuf_unittest::ComplexOptionType1, :bar, 1
    optional :int32, :baz, 2
    optional ::Protobuf_unittest::ComplexOptionType2::ComplexOptionType4, :fred, 3
    repeated ::Protobuf_unittest::ComplexOptionType2::ComplexOptionType4, :barney, 4
    # Extension Fields
    extensions 100...536870912
    optional :int32, :".protobuf_unittest.grault", 7650927, :extension => true
    optional ::Protobuf_unittest::ComplexOptionType1, :".protobuf_unittest.garply", 7649992, :extension => true
  end

  class ComplexOptionType3
    optional :int32, :qux, 1
  end

  class VariousComplexOptions
    # Message Options
    set_option :".protobuf_unittest.ComplexOptionType2.ComplexOptionType4.complex_opt4", { :waldo => 1971 }
    set_option :".protobuf_unittest.complex_opt3", { :qux => 9 }
    set_option :".protobuf_unittest.repeated_opt1", [1, 2]
    set_option :".protobuf_unittest.repeated_opt2", [{ :qux => 3 }, { :qux => 4 }]
    set_option :".protobuf_unittest.complex_opt2", { :bar => { :foo => 743, :".protobuf_unittest.corge" => { :qux => 2008 }, :".protobuf_unittest.quux" => 1999 }, :baz => 987, :fred => { :waldo => 321 }, :barney => [{ :waldo => 101 }, { :waldo => 212 }], :".protobuf_unittest.garply" => { :foo => 741, :".protobuf_unittest.corge" => { :qux => 2121 }, :".protobuf_unittest.quux" => 1998 }, :".protobuf_unittest.grault" => 654 }
    set_option :".protobuf_unittest.complex_opt1", { :foo => 42, :foo4 => [99, 88], :".protobuf_unittest.corge" => { :qux => 876 }, :".protobuf_unittest.quux" => 324 }

  end

  class AggregateMessageSet
    # Message Options
    set_option :message_set_wire_format, false

    # Extension Fields
    extensions 4...536870912
    optional ::Protobuf_unittest::AggregateMessageSetElement, :".protobuf_unittest.AggregateMessageSetElement.message_set_extension", 15447542, :extension => true
  end

  class AggregateMessageSetElement
    optional :string, :s, 1
  end

  class Aggregate
    optional :int32, :i, 1
    optional :string, :s, 2
    optional ::Protobuf_unittest::Aggregate, :sub, 3
    optional ::Google::Protobuf::FileOptions, :file, 4
    optional ::Protobuf_unittest::AggregateMessageSet, :mset, 5
  end

  class AggregateMessage
    # Message Options
    set_option :".protobuf_unittest.msgopt", { :i => 101, :s => "MessageAnnotation" }

    optional :int32, :fieldname, 1, :".protobuf_unittest.fieldopt" => { :s => "FieldAnnotation" }
  end

  class NestedOptionType
    class NestedMessage
      # Message Options
      set_option :".protobuf_unittest.message_opt1", 1001

      optional :int32, :nested_field, 1, :".protobuf_unittest.field_opt1" => 1002
    end

  end

  class OldOptionType
    required ::Protobuf_unittest::OldOptionType::TestEnum, :value, 1
  end

  class NewOptionType
    required ::Protobuf_unittest::NewOptionType::TestEnum, :value, 1
  end

  class TestMessageWithRequiredEnumOption
    # Message Options
    set_option :".protobuf_unittest.required_enum_opt", { :value => ::Protobuf_unittest::OldOptionType::TestEnum::OLD_VALUE }

  end


  ##
  # Extended Message Fields
  #
  class ::Google::Protobuf::FileOptions < ::Protobuf::Message
    optional :uint64, :".protobuf_unittest.file_opt1", 7736974, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.fileopt", 15478479, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.Aggregate.nested", 15476903, :extension => true
    optional :int32, :".protobuf_unittest.NestedOptionType.nested_extension", 7912573, :extension => true, :".protobuf_unittest.field_opt2" => 1005
  end

  class ::Google::Protobuf::MessageOptions < ::Protobuf::Message
    optional :int32, :".protobuf_unittest.message_opt1", 7739036, :extension => true
    optional :bool, :".protobuf_unittest.bool_opt", 7706090, :extension => true
    optional :int32, :".protobuf_unittest.int32_opt", 7705709, :extension => true
    optional :int64, :".protobuf_unittest.int64_opt", 7705542, :extension => true
    optional :uint32, :".protobuf_unittest.uint32_opt", 7704880, :extension => true
    optional :uint64, :".protobuf_unittest.uint64_opt", 7702367, :extension => true
    optional :sint32, :".protobuf_unittest.sint32_opt", 7701568, :extension => true
    optional :sint64, :".protobuf_unittest.sint64_opt", 7700863, :extension => true
    optional :fixed32, :".protobuf_unittest.fixed32_opt", 7700307, :extension => true
    optional :fixed64, :".protobuf_unittest.fixed64_opt", 7700194, :extension => true
    optional :sfixed32, :".protobuf_unittest.sfixed32_opt", 7698645, :extension => true
    optional :sfixed64, :".protobuf_unittest.sfixed64_opt", 7685475, :extension => true
    optional :float, :".protobuf_unittest.float_opt", 7675390, :extension => true
    optional :double, :".protobuf_unittest.double_opt", 7673293, :extension => true
    optional :string, :".protobuf_unittest.string_opt", 7673285, :extension => true
    optional :bytes, :".protobuf_unittest.bytes_opt", 7673238, :extension => true
    optional ::Protobuf_unittest::DummyMessageContainingEnum::TestEnumType, :".protobuf_unittest.enum_opt", 7673233, :extension => true
    optional ::Protobuf_unittest::DummyMessageInvalidAsOptionType, :".protobuf_unittest.message_type_opt", 7665967, :extension => true
    optional ::Protobuf_unittest::ComplexOptionType1, :".protobuf_unittest.complex_opt1", 7646756, :extension => true
    optional ::Protobuf_unittest::ComplexOptionType2, :".protobuf_unittest.complex_opt2", 7636949, :extension => true
    optional ::Protobuf_unittest::ComplexOptionType3, :".protobuf_unittest.complex_opt3", 7636463, :extension => true
    repeated :int32, :".protobuf_unittest.repeated_opt1", 7636464, :extension => true
    repeated ::Protobuf_unittest::ComplexOptionType3, :".protobuf_unittest.repeated_opt2", 7636465, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.msgopt", 15480088, :extension => true
    optional ::Protobuf_unittest::OldOptionType, :".protobuf_unittest.required_enum_opt", 106161807, :extension => true
    optional ::Protobuf_unittest::ComplexOptionType2::ComplexOptionType4, :".protobuf_unittest.ComplexOptionType2.ComplexOptionType4.complex_opt4", 7633546, :extension => true
  end

  class ::Google::Protobuf::FieldOptions < ::Protobuf::Message
    optional :fixed64, :".protobuf_unittest.field_opt1", 7740936, :extension => true
    optional :int32, :".protobuf_unittest.field_opt2", 7753913, :default => 42, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.fieldopt", 15481374, :extension => true
  end

  class ::Google::Protobuf::EnumOptions < ::Protobuf::Message
    optional :sfixed32, :".protobuf_unittest.enum_opt1", 7753576, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.enumopt", 15483218, :extension => true
  end

  class ::Google::Protobuf::EnumValueOptions < ::Protobuf::Message
    optional :int32, :".protobuf_unittest.enum_value_opt1", 1560678, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.enumvalopt", 15486921, :extension => true
  end

  class ::Google::Protobuf::ServiceOptions < ::Protobuf::Message
    optional :sint64, :".protobuf_unittest.service_opt1", 7887650, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.serviceopt", 15497145, :extension => true
  end

  class ::Google::Protobuf::MethodOptions < ::Protobuf::Message
    optional ::Protobuf_unittest::MethodOpt1, :".protobuf_unittest.method_opt1", 7890860, :extension => true
    optional ::Protobuf_unittest::Aggregate, :".protobuf_unittest.methodopt", 15512713, :extension => true
  end


  ##
  # Service Classes
  #
  class TestServiceWithCustomOptions < ::Protobuf::Rpc::Service
    set_option :".protobuf_unittest.service_opt1", -9876543210
    rpc :foo, ::Protobuf_unittest::CustomOptionFooRequest, ::Protobuf_unittest::CustomOptionFooResponse do
      set_option :".protobuf_unittest.method_opt1", ::Protobuf_unittest::MethodOpt1::METHODOPT1_VAL2
    end
  end

  class AggregateService < ::Protobuf::Rpc::Service
    set_option :".protobuf_unittest.serviceopt", { :s => "ServiceAnnotation" }
    rpc :method, ::Protobuf_unittest::AggregateMessage, ::Protobuf_unittest::AggregateMessage do
      set_option :".protobuf_unittest.methodopt", { :s => "MethodAnnotation" }
    end
  end

end

