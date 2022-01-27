# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'


##
# Imports
#
require 'protos/resource.pb'

module Test
  ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

  ##
  # Enum Classes
  #
  class EnumTestType < ::Protobuf::Enum
    define :ZERO, 0
    define :ONE, 1
    define :TWO, 2
  end

  class AliasedEnum < ::Protobuf::Enum
    set_option :allow_alias, true

    define :THREE, 3
    define :TRES, 3
    define :FOUR, 4
    define :CUATRO, 4
  end


  ##
  # Message Classes
  #
  class EnumTestMessage < ::Protobuf::Message; end


  ##
  # Message Fields
  #
  class EnumTestMessage
    optional ::Test::EnumTestType, :non_default_enum, 1
    optional ::Test::EnumTestType, :default_enum, 2, :default => ::Test::EnumTestType::ONE
    repeated ::Test::EnumTestType, :repeated_enums, 3
    optional ::Test::AliasedEnum, :alias_non_default_enum, 4
    optional ::Test::AliasedEnum, :alias_default_enum, 5, :default => ::Test::AliasedEnum::CUATRO
    repeated ::Test::AliasedEnum, :alias_repeated_enums, 6
  end


  ##
  # Extended Message Fields
  #
  class ::Test::Resource < ::Protobuf::Message
    optional :int32, :".test.ext_other_file_defined_field", 200, :extension => true
  end

end

