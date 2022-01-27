require 'set'

require 'protobuf/rpc/servers/socket/worker'

module Protobuf
  module Rpc
    module Socket
      class Server
        include ::Protobuf::Logging

        AUTO_COLLECT_TIMEOUT = 5 # seconds

        private

        attr_accessor :threshold, :host, :port, :backlog
        attr_writer :running

        public

        attr_reader :running
        alias :running? running

        def initialize(options)
          self.running = false
          self.host = options.fetch(:host)
          self.port = options.fetch(:port)
          self.backlog = options.fetch(:backlog, 100)
          self.threshold = options.fetch(:threshold, 100)
        end

        def threads
          @threads ||= []
        end

        def working
          @working ||= Set.new
        end

        def cleanup?
          # every `threshold` connections run a cleanup routine after closing the response
          !threads.empty? && threads.size % threshold == 0
        end

        def cleanup_threads
          logger.debug { sign_message("Thread cleanup - #{threads.size} - start") }

          threads.delete_if do |hash|
            unless (thread = hash.fetch(:thread)).alive?
              thread.join
              working.delete(hash.fetch(:socket))
            end
          end

          logger.debug { sign_message("Thread cleanup - #{threads.size} - complete") }
        end

        def log_signature
          @_log_signature ||= "[server-#{self.class.name}]"
        end

        def new_worker(socket)
          Thread.new(socket) do |sock|
            ::Protobuf::Rpc::Socket::Worker.new(sock, &:close)
          end
        end

        def run
          logger.debug { sign_message("Run") }

          server = ::TCPServer.new(host, port)
          fail "The server was unable to start properly." if server.closed?

          begin
            server.listen(backlog)
            listen_fds = [server]
            self.running = true

            while running?
              logger.debug { sign_message("Waiting for connections") }
              ready_cnxns = begin
                IO.select(listen_fds, [], [], AUTO_COLLECT_TIMEOUT)
              rescue IOError
                nil
              end

              if ready_cnxns
                ready_cnxns.first.each do |client|
                  case
                  when !running?
                    # no-op
                  when client == server
                    logger.debug { sign_message("Accepted new connection") }
                    client, _sockaddr = server.accept
                    listen_fds << client
                  else
                    unless working.include?(client)
                      working << listen_fds.delete(client)
                      logger.debug { sign_message("Working") }
                      threads << { :thread => new_worker(client), :socket => client }

                      cleanup_threads if cleanup?
                    end
                  end
                end
              elsif threads.size > 1
                # Run a cleanup if select times out while waiting
                cleanup_threads
              end
            end
          ensure
            server.close
          end
        end

        def stop
          self.running = false
        end
      end
    end
  end
end
