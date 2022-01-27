# frozen_string_literal: true

module Faraday
  module Retry
    # This class provides the main implementation for your middleware.
    # Your middleware can implement any of the following methods:
    # * on_request - called when the request is being prepared
    # * on_complete - called when the response is being processed
    #
    # Optionally, you can also override the following methods from Faraday::Middleware
    # * initialize(app, options = {}) - the initializer method
    # * call(env) - the main middleware invocation method.
    #   This already calls on_request and on_complete, so you normally don't need to override it.
    #   You may need to in case you need to "wrap" the request or need more control
    #   (see "retry" middleware: https://github.com/lostisland/faraday/blob/main/lib/faraday/request/retry.rb#L142).
    #   IMPORTANT: Remember to call `@app.call(env)` or `super` to not interrupt the middleware chain!
    class Middleware < Faraday::Middleware
      DEFAULT_EXCEPTIONS = [
        Errno::ETIMEDOUT, 'Timeout::Error',
        Faraday::TimeoutError, Faraday::RetriableResponse
      ].freeze
      IDEMPOTENT_METHODS = %i[delete get head options put].freeze

      # Options contains the configurable parameters for the Retry middleware.
      class Options < Faraday::Options.new(:max, :interval, :max_interval,
                                           :interval_randomness,
                                           :backoff_factor, :exceptions,
                                           :methods, :retry_if, :retry_block,
                                           :retry_statuses)

        DEFAULT_CHECK = ->(_env, _exception) { false }

        def self.from(value)
          if value.is_a?(Integer)
            new(value)
          else
            super(value)
          end
        end

        def max
          (self[:max] ||= 2).to_i
        end

        def interval
          (self[:interval] ||= 0).to_f
        end

        def max_interval
          (self[:max_interval] ||= Float::MAX).to_f
        end

        def interval_randomness
          (self[:interval_randomness] ||= 0).to_f
        end

        def backoff_factor
          (self[:backoff_factor] ||= 1).to_f
        end

        def exceptions
          Array(self[:exceptions] ||= DEFAULT_EXCEPTIONS)
        end

        def methods
          Array(self[:methods] ||= IDEMPOTENT_METHODS)
        end

        def retry_if
          self[:retry_if] ||= DEFAULT_CHECK
        end

        def retry_block
          self[:retry_block] ||= proc {} # rubocop:disable Lint/EmptyBlock
        end

        def retry_statuses
          Array(self[:retry_statuses] ||= [])
        end
      end

      # @param app [#call]
      # @param options [Hash]
      # @option options [Integer] :max (2) Maximum number of retries
      # @option options [Integer] :interval (0) Pause in seconds between retries
      # @option options [Integer] :interval_randomness (0) The maximum random
      #   interval amount expressed as a float between
      #   0 and 1 to use in addition to the interval.
      # @option options [Integer] :max_interval (Float::MAX) An upper limit
      #   for the interval
      # @option options [Integer] :backoff_factor (1) The amount to multiply
      #   each successive retry's interval amount by in order to provide backoff
      # @option options [Array] :exceptions ([ Errno::ETIMEDOUT,
      #   'Timeout::Error', Faraday::TimeoutError, Faraday::RetriableResponse])
      #   The list of exceptions to handle. Exceptions can be given as
      #   Class, Module, or String.
      # @option options [Array] :methods (the idempotent HTTP methods
      #   in IDEMPOTENT_METHODS) A list of HTTP methods to retry without
      #   calling retry_if. Pass an empty Array to call retry_if
      #   for all exceptions.
      # @option options [Block] :retry_if (false) block that will receive
      #   the env object and the exception raised
      #   and should decide if the code should retry still the action or
      #   not independent of the retry count. This would be useful
      #   if the exception produced is non-recoverable or if the
      #   the HTTP method called is not idempotent.
      # @option options [Block] :retry_block block that is executed before
      #   every retry. Request environment, middleware options, current number
      #   of retries and the exception is passed to the block as parameters.
      # @option options [Array] :retry_statuses Array of Integer HTTP status
      #   codes or a single Integer value that determines whether to raise
      #   a Faraday::RetriableResponse exception based on the HTTP status code
      #   of an HTTP response.
      def initialize(app, options = nil)
        super(app)
        @options = Options.from(options)
        @errmatch = build_exception_matcher(@options.exceptions)
      end

      def calculate_sleep_amount(retries, env)
        retry_after = calculate_retry_after(env)
        retry_interval = calculate_retry_interval(retries)

        return if retry_after && retry_after > @options.max_interval

        if retry_after && retry_after >= retry_interval
          retry_after
        else
          retry_interval
        end
      end

      # @param env [Faraday::Env]
      def call(env)
        retries = @options.max
        request_body = env[:body]
        begin
          # after failure env[:body] is set to the response body
          env[:body] = request_body
          @app.call(env).tap do |resp|
            raise Faraday::RetriableResponse.new(nil, resp) if @options.retry_statuses.include?(resp.status)
          end
        rescue @errmatch => e
          if retries.positive? && retry_request?(env, e)
            retries -= 1
            rewind_files(request_body)
            if (sleep_amount = calculate_sleep_amount(retries + 1, env))
              @options.retry_block.call(env, @options, retries, e)
              sleep sleep_amount
              retry
            end
          end

          raise unless e.is_a?(Faraday::RetriableResponse)

          e.response
        end
      end

      # An exception matcher for the rescue clause can usually be any object
      # that responds to `===`, but for Ruby 1.8 it has to be a Class or Module.
      #
      # @param exceptions [Array]
      # @api private
      # @return [Module] an exception matcher
      def build_exception_matcher(exceptions)
        matcher = Module.new
        (
          class << matcher
            self
          end).class_eval do
          define_method(:===) do |error|
            exceptions.any? do |ex|
              if ex.is_a? Module
                error.is_a? ex
              else
                Object.const_defined?(ex.to_s) && error.is_a?(Object.const_get(ex.to_s))
              end
            end
          end
        end
        matcher
      end

      private

      def retry_request?(env, exception)
        @options.methods.include?(env[:method]) ||
          @options.retry_if.call(env, exception)
      end

      def rewind_files(body)
        return unless defined?(UploadIO)
        return unless body.is_a?(Hash)

        body.each do |_, value|
          value.rewind if value.is_a?(UploadIO)
        end
      end

      # MDN spec for Retry-After header:
      # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Retry-After
      def calculate_retry_after(env)
        response_headers = env[:response_headers]
        return unless response_headers

        retry_after_value = env[:response_headers]['Retry-After']

        # Try to parse date from the header value
        begin
          datetime = DateTime.rfc2822(retry_after_value)
          datetime.to_time - Time.now.utc
        rescue ArgumentError
          retry_after_value.to_f
        end
      end

      def calculate_retry_interval(retries)
        retry_index = @options.max - retries
        current_interval = @options.interval *
                           (@options.backoff_factor**retry_index)
        current_interval = [current_interval, @options.max_interval].min
        random_interval = rand * @options.interval_randomness.to_f *
                          @options.interval

        current_interval + random_interval
      end
    end
  end
end
