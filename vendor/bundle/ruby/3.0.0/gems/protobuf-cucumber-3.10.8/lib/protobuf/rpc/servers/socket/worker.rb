require 'protobuf/rpc/server'
require 'protobuf/logging'

module Protobuf
  module Rpc
    module Socket
      class Worker
        include ::Protobuf::Rpc::Server
        include ::Protobuf::Logging

        def initialize(sock, &complete_cb)
          @socket = sock
          @complete_cb = complete_cb

          data = read_data
          return unless data

          gc_pause do
            encoded_response = handle_request(data)
            send_data(encoded_response)
          end
        end

        def read_data
          size_io = StringIO.new

          until (size_reader = @socket.getc) == "-"
            size_io << size_reader
          end
          str_size_io = size_io.string

          @socket.read(str_size_io.to_i)
        end

        def send_data(data)
          fail 'Socket closed unexpectedly' unless socket_writable?
          response_buffer = Protobuf::Rpc::Buffer.new(:write)
          response_buffer.set_data(data)

          @socket.write(response_buffer.write)
          @socket.flush

          @complete_cb.call(@socket)
        end

        def log_signature
          @_log_signature ||= "[server-#{self.class}-#{object_id}]"
        end

        def socket_writable?
          ! @socket.nil? && ! @socket.closed?
        end
      end
    end
  end
end
