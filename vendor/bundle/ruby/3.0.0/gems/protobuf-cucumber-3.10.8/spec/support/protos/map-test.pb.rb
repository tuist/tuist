# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'

module Foo
  ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

  ##
  # Enum Classes
  #
  class Frobnitz < ::Protobuf::Enum
    define :FROB, 1
    define :NITZ, 2
  end


  ##
  # Message Classes
  #
  class Baz < ::Protobuf::Message
    class DoesNotLookLikeMapEntry < ::Protobuf::Message; end

  end

  class Bar < ::Protobuf::Message
  end



  ##
  # Message Fields
  #
  class Baz
    class DoesNotLookLikeMapEntry
      optional :string, :key, 1
      optional :string, :value, 2
    end

    map :string, :string, :looks_like_map, 1
    repeated ::Foo::Baz::DoesNotLookLikeMapEntry, :does_not_look_like_map, 2
  end

  class Bar
    map :sint32, ::Foo::Baz, :sint32_to_baz, 1
    map :sint64, ::Foo::Baz, :sint64_to_baz, 2
    map :int32, ::Foo::Baz, :int32_to_baz, 3
    map :int64, ::Foo::Baz, :int64_to_baz, 4
    map :uint32, ::Foo::Baz, :uint32_to_baz, 5
    map :uint64, ::Foo::Baz, :uint64_to_baz, 6
    map :string, ::Foo::Baz, :string_to_baz, 7
    map :sint32, ::Foo::Frobnitz, :sint32_to_frobnitz, 8
    map :sint64, ::Foo::Frobnitz, :sint64_to_frobnitz, 9
    map :int32, ::Foo::Frobnitz, :int32_to_frobnitz, 10
    map :int64, ::Foo::Frobnitz, :int64_to_frobnitz, 11
    map :uint32, ::Foo::Frobnitz, :uint32_to_frobnitz, 12
    map :uint64, ::Foo::Frobnitz, :uint64_to_frobnitz, 13
    map :string, ::Foo::Frobnitz, :string_to_frobnitz, 14
    map :sint32, :string, :sint32_to_string, 15
    map :sint64, :string, :sint64_to_string, 16
    map :int32, :string, :int32_to_string, 17
    map :int64, :string, :int64_to_string, 18
    map :uint32, :string, :uint32_to_string, 19
    map :uint64, :string, :uint64_to_string, 20
    map :string, :string, :string_to_string, 21
    map :sint32, :float, :sint32_to_float, 22
    map :sint64, :float, :sint64_to_float, 23
    map :int32, :float, :int32_to_float, 24
    map :int64, :float, :int64_to_float, 25
    map :uint32, :float, :uint32_to_float, 26
    map :uint64, :float, :uint64_to_float, 27
    map :string, :float, :string_to_float, 28
    map :sint32, :double, :sint32_to_double, 29
    map :sint64, :double, :sint64_to_double, 30
    map :int32, :double, :int32_to_double, 31
    map :int64, :double, :int64_to_double, 32
    map :uint32, :double, :uint32_to_double, 33
    map :uint64, :double, :uint64_to_double, 34
    map :string, :double, :string_to_double, 35
  end

end

