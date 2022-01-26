# frozen_string_literal: true

module Cucumber
  module Formatter
    module Interceptor
      class Pipe
        attr_reader :pipe

        def initialize(pipe)
          @pipe = pipe
          @buffer = StringIO.new
          @wrapped = true
          @lock = Mutex.new
        end

        def write(str)
          @lock.synchronize do
            @buffer << str if @wrapped
            return @pipe.write(str)
          end
        end

        def buffer_string
          @lock.synchronize do
            return @buffer.string.dup
          end
        end

        def unwrap!
          @wrapped = false
          @pipe
        end

        def method_missing(method, *args, &blk)
          @pipe.respond_to?(method) ? @pipe.send(method, *args, &blk) : super
        end

        def respond_to_missing?(method, include_private = false)
          super || @pipe.respond_to?(method, include_private)
        end

        def self.validate_pipe(pipe)
          raise ArgumentError, '#wrap only accepts :stderr or :stdout' unless %i[stdout stderr].include? pipe
        end

        def self.unwrap!(pipe)
          validate_pipe pipe
          wrapped = nil
          case pipe
          when :stdout
            wrapped = $stdout
            $stdout = wrapped.unwrap! if $stdout.respond_to?(:unwrap!)
          when :stderr
            wrapped = $stderr
            $stderr = wrapped.unwrap! if $stderr.respond_to?(:unwrap!)
          end
          wrapped
        end

        def self.wrap(pipe)
          validate_pipe pipe

          case pipe
          when :stderr
            $stderr = new($stderr)
            $stderr
          when :stdout
            $stdout = new($stdout)
            $stdout
          end
        end
      end
    end
  end
end
