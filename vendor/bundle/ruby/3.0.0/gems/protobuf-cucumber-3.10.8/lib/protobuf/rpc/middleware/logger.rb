module Protobuf
  module Rpc
    module Middleware
      class Logger
        def initialize(app)
          @app = app
        end

        # TODO: Figure out how to control when logs are flushed
        def call(env)
          dup._call(env)
        end

        def _call(env)
          instrumenter.start
          instrumenter.flush(env) # Log request stats

          env = @app.call(env)

          instrumenter.stop
          instrumenter.flush(env) # Log response stats

          env
        end

        private

        def instrumenter
          @instrumenter ||= Instrumenter.new
        end

        # TODO: Replace this with ActiveSupport::Notifications and log subscribers
        # TODO: Consider adopting Rails-style logging so we can track serialization
        # time as well as ActiveRecord time, etc.:
        #
        #     Started GET "/" for 127.0.0.1 at 2014-02-12 09:40:29 -0700
        #     Processing by ReleasesController#index as HTML
        #       Rendered releases/_release.html.erb (0.0ms)
        #       Rendered releases/_release.html.erb (0.0ms)
        #       Rendered releases/_release.html.erb (0.0ms)
        #       Rendered releases/_release.html.erb (0.0ms)
        #       Rendered releases/index.html.erb within layouts/application (11.0ms)
        #     Completed 200 OK in 142ms (Views: 117.6ms | ActiveRecord: 1.7ms)
        #
        class Instrumenter
          attr_reader :env

          def flush(env)
            ::Protobuf::Logging.logger.info { to_s(env) }
          end

          def start
            @start_time = ::Time.now.utc
          end

          def stop
            @end_time = ::Time.now.utc
          end

          def to_s(env)
            @env = env

            [
              "[SRV]",
              env.client_host,
              env.worker_id,
              rpc,
              sizes,
              elapsed_time,
              @end_time.try(:iso8601),
            ].compact.join(' - ')
          end

          private

          def elapsed_time
            (@start_time && @end_time ? "#{(@end_time - @start_time).round(4)}s" : nil)
          end

          def rpc
            env.service_name && env.method_name ? "#{env.service_name}##{env.method_name}" : nil
          end

          def sizes
            if env.encoded_response?
              "#{env.encoded_request.size}B/#{env.encoded_response.size}B"
            else
              "#{env.encoded_request.size}B/-"
            end
          end
        end
      end
    end
  end
end
