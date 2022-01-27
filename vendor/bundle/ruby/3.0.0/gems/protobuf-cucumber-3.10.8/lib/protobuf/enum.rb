require 'delegate'

##
# Adding extension to Numeric until
# we can get people to stop calling #value
# on Enum instances.
#
::Protobuf.deprecator.define_deprecated_methods(Numeric, :value => :to_int)

module Protobuf
  class Enum < SimpleDelegator
    # Public: Allows setting Options on the Enum class.
    ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::EnumOptions }

    def self.aliases_allowed?
      get_option(:allow_alias)
    end

    # Public: Get all integer tags defined by this enum.
    #
    # Examples
    #
    #   class StateMachine < ::Protobuf::Enum
    #     set_option :allow_alias
    #     define :ON, 1
    #     define :STARTED, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine.all_tags #=> [ 1, 2 ]
    #
    # Returns an array of unique integers.
    #
    def self.all_tags
      @all_tags ||= enums.map(&:to_i).uniq
    end

    # Internal: DSL method to create a new Enum. The given name will
    # become a constant for this Enum pointing to the new instance.
    #
    # Examples
    #
    #   class StateMachine < ::Protobuf::Enum
    #     define :ON, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine::ON  #=> #<StateMachine::ON=1>
    #   StateMachine::OFF #=> #<StateMachine::OFF=2>
    #
    # Returns nothing.
    #
    def self.define(name, tag)
      enum = new(self, name, tag)
      @enums ||= []
      @enums << enum
      # defining a new field for the enum will cause cached @values and @mapped_enums
      # to be incorrect; reset them
      @mapped_enums = @values = nil
      const_set(name, enum)
      mapped_enums
    end

    # Internal: A mapping of enum number -> enums defined
    # used for speeding up our internal enum methods.
    def self.mapped_enums
      @mapped_enums ||= enums.each_with_object({}) do |enum, hash|
        list = hash[enum.to_i] ||= []
        list << enum
      end
    end

    # Public: All defined enums.
    #
    class << self
      attr_reader :enums
    end

    # Public: Get an array of Enum objects with the given tag.
    #
    # tag - An object that responds to to_i.
    #
    # Examples
    #
    #   class StateMachine < ::Protobuf::Enum
    #     set_option :allow_alias
    #     define :ON, 1
    #     define :STARTED, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine.enums_for_tag(1) #=> [ #<StateMachine::ON=1>, #<StateMachine::STARTED=1> ]
    #   StateMachine.enums_for_tag(2) #=> [ #<StateMachine::OFF=2> ]
    #
    # Returns an array with zero or more Enum objects or nil.
    #
    def self.enums_for_tag(tag)
      tag && mapped_enums[tag.to_i] || []
    end

    # Public: Get the Enum associated with the given name.
    #
    # name - A string-like object. Case-sensitive.
    #
    # Example
    #
    #   class StateMachine < ::Protobuf::Enum
    #     define :ON, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine.enum_for_name(:ON)  # => #<StateMachine::ON=1>
    #   StateMachine.enum_for_name("ON") # => #<StateMachine::ON=1>
    #   StateMachine.enum_for_name(:on)  # => nil
    #   StateMachine.enum_for_name(:FOO) # => nil
    #
    # Returns the Enum object with the given name or nil.
    #
    def self.enum_for_name(name)
      const_get(name)
    rescue ::NameError
      nil
    end

    # Public: Get the Enum object corresponding to the given tag.
    #
    # tag - An object that responds to to_i.
    #
    # Returns an Enum object or nil. If the tag corresponds to multiple
    #   Enums, the first enum defined will be returned.
    #
    def self.enum_for_tag(tag)
      tag && (mapped_enums[tag.to_i] || []).first
    end

    def self.enum_for_tag_integer(tag)
      (@mapped_enums[tag] || []).first
    end

    # Public: Get an Enum by a variety of type-checking mechanisms.
    #
    # candidate - An Enum, Numeric, String, or Symbol object.
    #
    # Example
    #
    #   class StateMachine < ::Protobuf::Enum
    #     set_option :allow_alias
    #     define :ON, 1
    #     define :STARTED, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine.fetch(StateMachine::ON)  # => #<StateMachine::ON=1>
    #   StateMachine.fetch(:ON)               # => #<StateMachine::ON=1>
    #   StateMachine.fetch("STARTED")         # => #<StateMachine::STARTED=1>
    #   StateMachine.fetch(1)                 # => [ #<StateMachine::ON=1>, #<StateMachine::STARTED=1> ]
    #
    # Returns an Enum object or nil.
    #
    def self.fetch(candidate)
      return enum_for_tag_integer(candidate) if candidate.is_a?(::Integer)

      case candidate
      when self
        candidate
      when ::Numeric
        enum_for_tag(candidate.to_i)
      when ::String, ::Symbol
        enum_for_name(candidate)
      else
        nil
      end
    end

    # Public: Get the Symbol name associated with the given number.
    #
    # number - An object that responds to to_i.
    #
    # Examples
    #
    #   # Without aliases
    #   class StateMachine < ::Protobuf::Enum
    #     define :ON, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine.name_for_tag(1) # => :ON
    #   StateMachine.name_for_tag(2) # => :OFF
    #   StateMachine.name_for_tag(3) # => nil
    #
    #   # With aliases
    #   class StateMachine < ::Protobuf::Enum
    #     set_option :allow_alias
    #     define :STARTED, 1
    #     define :ON, 1
    #     define :OFF, 2
    #   end
    #
    #   StateMachine.name_for_tag(1) # => :STARTED
    #   StateMachine.name_for_tag(2) # => :OFF
    #
    # Returns the symbol name of the enum constant given it's associated tag or nil.
    #   If the given tag has multiple names associated (due to allow_alias)
    #   the first defined name will be returned.
    #
    def self.name_for_tag(tag)
      enum_for_tag(tag).try(:name)
    end

    # Public: Check if the given tag is defined by this Enum.
    #
    # number - An object that responds to to_i.
    #
    # Returns a boolean.
    #
    def self.valid_tag?(tag)
      tag.respond_to?(:to_i) && mapped_enums.key?(tag.to_i)
    end

    # Public: [DEPRECATED] Return a hash of Enum objects keyed
    # by their :name.
    #
    def self.values
      @values ||= enums.each_with_object({}) do |enum, hash|
        hash[enum.name] = enum
      end
    end

    ##
    # Class Deprecations
    #
    class << self
      ::Protobuf.deprecator.define_deprecated_methods(
        self,
        :enum_by_value => :enum_for_tag,
        :name_by_value => :name_for_tag,
        :get_name_by_tag => :name_for_tag,
        :value_by_name => :enum_for_name,
      )

      ::Protobuf.deprecator.deprecate_methods(self, :values => :enums)
    end

    ##
    # Attributes
    #

    private

    attr_writer :parent_class, :name, :tag

    public

    attr_reader :parent_class, :name, :tag

    ##
    # Instance Methods
    #

    def initialize(parent_class, name, tag)
      self.parent_class = parent_class
      self.name = name
      self.tag = tag
      super(tag)
    end

    # Custom equality method since otherwise identical values from different
    # enums will be considered equal by Integer's equality method (or
    # Fixnum's on Ruby < 2.4.0).
    #
    def ==(other)
      if other.is_a?(Protobuf::Enum)
        parent_class == other.parent_class && tag == other.tag
      elsif tag.class == other.class
        tag == other
      else
        false
      end
    end

    # Overriding the class so ActiveRecord/Arel visitor will visit the enum as an
    # Integer.
    #
    def class
      # This is done for backward compatibility for < 2.4.0. This ensures that
      # if Ruby version >= 2.4.0, this will return Integer. If below, then will
      # return Fixnum.
      #
      # This prevents the constant deprecation warnings on Fixnum.
      tag.class
    end

    # Protobuf::Enum delegates methods to Fixnum, which has a custom hash equality method (`eql?`)
    # This causes enum values to be equivalent when using `==`, `===`, `equals?`, but not `eql?`**:
    #
    #   2.3.7 :002 > ::Test::EnumTestType::ZERO.eql?(::Test::EnumTestType::ZERO)
    #    => false
    #
    # However, they are equilvalent to their tag value:
    #
    #   2.3.7 :002 > ::Test::EnumTestType::ZERO.eql?(::Test::EnumTestType::ZERO.tag)
    #    => true
    #
    # **The implementation changed in Ruby 2.5, so this only affects Ruby versions less than v2.4.
    #
    # Use the hash equality implementation from Object#eql?, which is equivalent to == instead.
    #
    def eql?(other)
      self == other
    end

    def inspect
      "\#<Protobuf::Enum(#{parent_class})::#{name}=#{tag}>"
    end

    def to_int
      tag.to_int
    end

    # This fixes a reflection bug in JrJackson RubyAnySerializer that does not
    # render Protobuf enums correctly because to_json is not defined. It takes
    # any number of arguments to support the JSON gem trying to pass an argument.
    # NB: This method is required to return a string and not an integer.
    #
    def to_json(*)
      to_s
    end

    def to_s(format = :tag)
      case format
      when :tag
        to_i.to_s
      when :name
        name.to_s
      else
        to_i.to_s
      end
    end

    # Re-implement `try` in order to fix the problem where
    # the underlying fixnum doesn't respond to all methods (e.g. name or tag).
    # If we respond to the first argument, `__send__` the args. Otherwise,
    # delegate the `try` call to the underlying vlaue fixnum.
    #
    def try(*args, &block)
      case
      when args.empty? && block_given?
        yield self
      when respond_to?(args.first)
        __send__(*args, &block)
      else
        @tag.try(*args, &block)
      end
    end

    ##
    # Instance Aliases
    #
    alias :to_i tag
    alias :to_hash_value tag
    alias :to_json_hash_value tag

    ::Protobuf.deprecator.define_deprecated_methods(self, :value => :to_i)
  end
end
