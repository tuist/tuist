require 'resolv'

module Protobuf
  module Rpc
    module Zmq

      ADDRESS_MATCH = /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/
      WORKER_READY_MESSAGE = "\1".freeze
      CHECK_AVAILABLE_MESSAGE = "\3".freeze
      NO_WORKERS_AVAILABLE = "\4".freeze
      WORKERS_AVAILABLE = "\5".freeze
      EMPTY_STRING = "".freeze

      module Util
        include ::Protobuf::Logging

        def self.included(base)
          base.extend(::Protobuf::Rpc::Zmq::Util)
        end

        def zmq_error_check(return_code, source = nil)
          return if ::ZMQ::Util.resultcode_ok?(return_code)

          fail <<-ERROR
          Last ZMQ API call #{source ? "to #{source}" : ''} failed with "#{::ZMQ::Util.error_string}".

          #{caller(1).join($INPUT_RECORD_SEPARATOR)}
          ERROR
        end

        def log_signature
          unless @_log_signature
            name = (self.class == Class ? self.name : self.class.name)
            @_log_signature = "[server-#{name}-#{object_id}]"
          end

          @_log_signature
        end

        def resolve_ip(hostname)
          ::Resolv.getaddresses(hostname).find do |address|
            address =~ ADDRESS_MATCH
          end
        end
      end
    end
  end
end
