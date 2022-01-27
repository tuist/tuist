require 'logger'

module Protobuf
  module Logging
    def self.initialize_logger(log_target = $stdout, log_level = ::Logger::INFO)
      @logger = Logger.new(log_target)
      @logger.level = log_level
      @logger
    end

    def self.logger
      defined?(@logger) ? @logger : initialize_logger
    end

    class << self
      attr_writer :logger
    end

    def logger
      ::Protobuf::Logging.logger
    end

    def log_exception(ex)
      logger.error { ex.message }
      logger.error { ex.backtrace[0..5].join("\n") }
      logger.debug { ex.backtrace.join("\n") }
    end

    def log_signature
      @_log_signature ||= "[#{self.class == Class ? name : self.class.name}]"
    end

    def sign_message(message)
      "#{log_signature} #{message}"
    end
  end
end

# Inspired by [mperham](https://github.com/mperham/sidekiq)
