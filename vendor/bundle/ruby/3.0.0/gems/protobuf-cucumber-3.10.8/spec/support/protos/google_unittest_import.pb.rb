# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'


##
# Imports
#
require 'protos/google_unittest_import_public.pb'

module Protobuf_unittest_import
  ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

  ##
  # Enum Classes
  #
  class ImportEnum < ::Protobuf::Enum
    define :IMPORT_FOO, 7
    define :IMPORT_BAR, 8
    define :IMPORT_BAZ, 9
  end

  class ImportEnumForMap < ::Protobuf::Enum
    define :UNKNOWN, 0
    define :FOO, 1
    define :BAR, 2
  end


  ##
  # Message Classes
  #
  class ImportMessage < ::Protobuf::Message; end


  ##
  # File Options
  #
  set_option :java_package, "com.google.protobuf.test"
  set_option :optimize_for, ::Google::Protobuf::FileOptions::OptimizeMode::SPEED
  set_option :cc_enable_arenas, true


  ##
  # Message Fields
  #
  class ImportMessage
    optional :int32, :d, 1
  end

end

