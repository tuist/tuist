require "socket"

module Protobuf
  module Rpc
    module Connectors
      class Ping
        attr_reader :host, :port

        def initialize(host, port)
          @host = host
          @port = port
        end

        def online?
          socket = tcp_socket
          socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_LINGER, [1, 0].pack('ii'))

          true
        rescue
          false
        ensure
          begin
            socket && socket.close
          rescue IOError
            nil
          end
        end

        def timeout
          @timeout ||= begin
            if ::ENV.key?("PB_RPC_PING_PORT_TIMEOUT")
              ::ENV["PB_RPC_PING_PORT_TIMEOUT"].to_f / 1000
            else
              0.2 # 200 ms
            end
          end
        end

        private

        def tcp_socket
          # Reference: http://stackoverflow.com/a/21014439/1457934
          socket = ::Socket.new(family, ::Socket::SOCK_STREAM, 0)
          socket.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_NODELAY, 1)
          socket.connect_nonblock(sockaddr)
          socket
        rescue ::IO::WaitWritable
          # IO.select will block until the socket is writable or the timeout
          # is exceeded - whichever comes first.
          if ::IO.select(nil, [socket], nil, timeout)
            begin
              # Verify there is now a good connection
              socket.connect_nonblock(sockaddr)
              socket
            rescue ::Errno::EISCONN
              # Socket is connected.
              socket
            rescue
              # An unexpected exception was raised - the connection is no good.
              socket.close
              raise
            end
          else
            # IO.select returns nil when the socket is not ready before timeout
            # seconds have elapsed
            socket.close
            raise "Connection Timeout"
          end
        end

        def family
          @family ||= ::Socket.const_get(addrinfo[0][0])
        end

        def addrinfo
          @addrinfo ||= ::Socket.getaddrinfo(host, nil)
        end

        def ip
          @ip ||= addrinfo[0][3]
        end

        def sockaddr
          @sockaddr ||= ::Socket.pack_sockaddr_in(port, ip)
        end
      end
    end
  end
end
