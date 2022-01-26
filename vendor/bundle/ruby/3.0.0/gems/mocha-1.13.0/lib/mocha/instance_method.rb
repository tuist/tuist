require 'mocha/stubbed_method'

module Mocha
  class InstanceMethod < StubbedMethod
    private

    def mock_owner
      stubbee
    end

    def method_body(method)
      PRE_RUBY_V19 ? proc { |*args, &block| method.call(*args, &block) } : method
    end

    def stubbee_method(method_name)
      stubbee._method(method_name)
    end

    def original_method_owner
      stubbee.singleton_class
    end
  end
end
