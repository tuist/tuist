# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'

module Test
  ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

  ##
  # Message Classes
  #
  class Header < ::Protobuf::Message
    class Type < ::Protobuf::Enum
      define :PayloadTypeA, 1
      define :PayloadTypeB, 2
    end

  end

  class PayloadA < ::Protobuf::Message
    class Foo < ::Protobuf::Message; end

  end

  class PayloadB < ::Protobuf::Message
    class Foo < ::Protobuf::Message; end

  end



  ##
  # Message Fields
  #
  class Header
    required ::Test::Header::Type, :type, 1
    # Extension Fields
    extensions 100...536870912
    optional ::Test::PayloadA, :".test.PayloadA.payload", 100, :extension => true
  end

  class PayloadA
    class Foo
      optional :string, :foo_a, 1
    end

  end

  class PayloadB
    class Foo
      optional :string, :foo_b, 1
    end

  end

end

