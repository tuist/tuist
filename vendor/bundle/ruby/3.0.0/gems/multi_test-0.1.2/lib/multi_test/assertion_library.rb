require 'multi_test/minitest_world'

module MultiTest
  class AssertionLibrary
    def self.detect_best
      available.detect(&:require?)
    end

    def initialize(requirer, extender)
      @requirer = requirer
      @extender = extender
    end

    def require?
      begin
        @requirer.call
        true
      rescue LoadError
        false
      end
    end

    def extend_world(world)
      @extender.call(world)
    end

    private

    def self.null
      AssertionLibrary.new(
        proc { },
        proc { }
      )
    end

    def self.available
      @available ||= [
        AssertionLibrary.new(
          proc { require 'rspec/expectations' },
          proc { |object| object.extend(::RSpec::Matchers) }
        ),
        AssertionLibrary.new(
          proc {
            require 'spec/expectations'
            require 'spec/runner/differs/default'
            require 'ostruct'
          },
          proc { |object|
            options = OpenStruct.new(:diff_format => :unified, :context_lines => 3)
            Spec::Expectations.differ = Spec::Expectations::Differs::Default.new(options)
            object.extend(Spec::Matchers)
          }
        ),
        AssertionLibrary.new(
          proc { require 'minitest/assertions' },
          proc { |object| object.extend(MinitestWorld) }
        ),
        AssertionLibrary.new(
          proc { require 'minitest/unit' },
          proc { |object| object.extend(MiniTest::Assertions) }
        ),
        AssertionLibrary.new(
          proc { require 'test/unit/assertions' },
          proc { |object| object.extend(Test::Unit::Assertions) }
        ),
        # Null assertion library must come last to prevent exceptions if
        # unable to load a test framework
        AssertionLibrary.null
      ]
    end
  end
end

