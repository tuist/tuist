module Middleware
  # This provides a DSL for building up a stack of middlewares.
  #
  # This code is based heavily off of `Rack::Builder` and
  # `ActionDispatch::MiddlewareStack` in Rack and Rails, respectively.
  #
  # # Usage
  #
  # Building a middleware stack is very easy:
  #
  #     app = Middleware::Builder.new do
  #       use A
  #       use B
  #     end
  #
  #     # Call the middleware
  #     app.call(7)
  #
  class Builder
    # Initializes the builder. An optional block can be passed which
    # will be evaluated in the context of the instance.
    #
    # Example:
    #
    #     Builder.new do
    #       use A
    #       use B
    #     end
    #
    # @param [Hash] opts Options hash
    # @option opts [Class] :runner_class The class to wrap the middleware stack
    #   in which knows how to run them.
    # @yield [] Evaluated in this instance which allows you to use methods
    #   like {#use} and such.
    def initialize(opts=nil, &block)
      opts ||= {}
      @runner_class = opts[:runner_class] || Runner
      instance_eval(&block) if block_given?
    end

    # Returns a mergeable version of the builder. If `use` is called with
    # the return value of this method, then the stack will merge, instead
    # of being treated as a separate single middleware.
    def flatten
      lambda do |env|
        self.call(env)
      end
    end

    # Adds a middleware class to the middleware stack. Any additional
    # args and a block, if given, are saved and passed to the initializer
    # of the middleware.
    #
    # @param [Class] middleware The middleware class
    def use(middleware, *args, &block)
      if middleware.kind_of?(Builder)
        # Merge in the other builder's stack into our own
        self.stack.concat(middleware.stack)
      else
        self.stack << [middleware, args, block]
      end

      self
    end

    # Inserts a middleware at the given index or directly before the
    # given middleware object.
    def insert(index, middleware, *args, &block)
      index = self.index(index) unless index.is_a?(Integer)
      stack.insert(index, [middleware, args, block])
    end

    alias_method :insert_before, :insert

    # Inserts a middleware after the given index or middleware object.
    def insert_after(index, middleware, *args, &block)
      index = self.index(index) unless index.is_a?(Integer)
      raise "no such middleware to insert after: #{index.inspect}" unless index
      insert(index + 1, middleware, *args, &block)
    end

    # Replaces the given middlware object or index with the new
    # middleware.
    def replace(index, middleware, *args, &block)
      if index.is_a?(Integer)
        delete(index)
        insert(index, middleware, *args, &block)
      else
        insert_before(index, middleware, *args, &block)
        delete(index)
      end
    end

    # Deletes the given middleware object or index
    def delete(index)
      index = self.index(index) unless index.is_a?(Integer)
      stack.delete_at(index)
    end

    # Runs the builder stack with the given environment.
    def call(env=nil)
      to_app.call(env)
    end

    protected

    # Returns the numeric index for the given middleware object.
    #
    # @param [Object] object The item to find the index for
    # @return [Integer]
    def index(object)
      stack.each_with_index do |item, i|
        return i if item[0] == object
      end

      nil
    end

    # Returns the current stack of middlewares. You probably won't
    # need to use this directly, and it's recommended that you don't.
    #
    # @return [Array]
    def stack
      @stack ||= []
    end

    # Converts the builder stack to a runnable action sequence.
    #
    # @return [Object] A callable object
    def to_app
      @runner_class.new(stack.dup)
    end
  end
end
